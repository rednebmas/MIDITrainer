import Foundation

/// Represents a sequence that was answered incorrectly and is queued for re-asking.
///
/// Ladder semantics: `currentClearance` is the gap (in questions) before the
/// next re-ask. It starts at the base clearance setting and grows by one
/// clearance unit per successful re-ask; a failure steps it back one unit
/// (floor at base). The mistake clears once a successful re-ask happens at
/// `requiredClearance(clearance:minPasses:)` — a derived value, never stored,
/// so clearance/minPasses setting changes apply immediately to every row.
struct QueuedMistake: Equatable, Codable {
    /// Shared initial spacing for new mistakes (kept in one place to avoid drift between runtime and persistence).
    static let initialClearanceDistance = 3

    /// Unique identifier for this queued entry (database row ID).
    let id: Int64

    /// The seed used to regenerate the exact same sequence.
    let seed: UInt64

    /// The settings snapshot used to generate the sequence (captured at queue time).
    let settings: PracticeSettingsSnapshot

    /// Human-readable name of the melody source (e.g., "Art Pepper - Anthropology").
    let sourceName: String?

    /// Questions to wait between re-asks; one rung of the ladder per clearance unit.
    var currentClearance: Int

    /// Exact number of failures for this queued mistake (the initial failure counts as 1).
    var totalFailures: Int?

    /// Questions answered since this was queued or since its last re-ask.
    var questionsWaited: Int

    /// Whether this mistake is due to be re-asked (has waited enough questions).
    var isDue: Bool {
        questionsWaited >= currentClearance
    }

    /// The timestamp when this mistake was first queued.
    let queuedAt: Date

    /// The clearance `currentClearance` must reach before a successful re-ask
    /// clears this mistake. Failures inflate the requirement.
    func requiredClearance(clearance: Int, minPasses: Int) -> Int {
        clearance * max(minPasses, totalFailures ?? 1)
    }

    /// Clamps `currentClearance` into the valid ladder range for the given settings.
    func normalized(clearance: Int, minPasses: Int) -> QueuedMistake {
        var copy = self
        copy.currentClearance = min(
            max(clearance, currentClearance),
            requiredClearance(clearance: clearance, minPasses: minPasses)
        )
        return copy
    }

    /// Creates a new queued mistake with default initial values.
    init(id: Int64, seed: UInt64, settings: PracticeSettingsSnapshot, sourceName: String? = nil, queuedAt: Date = Date()) {
        self.id = id
        self.seed = seed
        self.settings = settings
        self.sourceName = sourceName
        self.currentClearance = Self.initialClearanceDistance
        self.totalFailures = 1
        self.questionsWaited = 0
        self.queuedAt = queuedAt
    }

    /// Creates a queued mistake with all values specified (for loading from persistence).
    init(
        id: Int64,
        seed: UInt64,
        settings: PracticeSettingsSnapshot,
        sourceName: String?,
        currentClearance: Int,
        totalFailures: Int?,
        questionsWaited: Int,
        queuedAt: Date
    ) {
        self.id = id
        self.seed = seed
        self.settings = settings
        self.sourceName = sourceName
        self.currentClearance = currentClearance
        self.totalFailures = totalFailures.map { max(1, $0) }
        self.questionsWaited = questionsWaited
        self.queuedAt = queuedAt
    }
}
