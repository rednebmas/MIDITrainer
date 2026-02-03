import Foundation

/// Represents a sequence that was answered incorrectly and is queued for re-asking.
struct QueuedMistake: Equatable, Codable {
    /// Shared initial spacing for new mistakes (kept in one place to avoid drift between runtime and persistence).
    static let initialClearanceDistance = 3

    /// How much to increase the minimum clearance distance when failing a re-ask.
    static let clearanceIncrement = 3
    
    /// Unique identifier for this queued entry (database row ID).
    let id: Int64

    /// The seed used to regenerate the exact same sequence.
    let seed: UInt64

    /// The settings snapshot used to generate the sequence (captured at queue time).
    let settings: PracticeSettingsSnapshot

    /// Human-readable name of the melody source (e.g., "Art Pepper - Anthropology").
    let sourceName: String?
    
    /// The minimum number of fresh questions required before this can be cleared.
    var minimumClearanceDistance: Int
    
    /// The number of fresh questions required before the next re-ask.
    var currentClearanceDistance: Int
    
    /// How many fresh questions have been answered since this was queued or last attempted.
    var questionsSinceQueued: Int
    
    /// Whether this mistake is due to be re-asked (has waited enough fresh questions).
    var isDue: Bool {
        questionsSinceQueued >= currentClearanceDistance
    }

    /// Total times this card has been failed (1 for initial failure + subsequent re-ask failures).
    var totalFailures: Int {
        1 + (minimumClearanceDistance - Self.initialClearanceDistance) / Self.clearanceIncrement
    }
    
    /// The timestamp when this mistake was first queued.
    let queuedAt: Date
    
    /// Creates a new queued mistake with default initial values.
    init(id: Int64, seed: UInt64, settings: PracticeSettingsSnapshot, sourceName: String? = nil, queuedAt: Date = Date()) {
        self.id = id
        self.seed = seed
        self.settings = settings
        self.sourceName = sourceName
        self.minimumClearanceDistance = Self.initialClearanceDistance
        self.currentClearanceDistance = Self.initialClearanceDistance
        self.questionsSinceQueued = 0
        self.queuedAt = queuedAt
    }

    /// Creates a queued mistake with all values specified (for loading from persistence).
    init(
        id: Int64,
        seed: UInt64,
        settings: PracticeSettingsSnapshot,
        sourceName: String?,
        minimumClearanceDistance: Int,
        currentClearanceDistance: Int,
        questionsSinceQueued: Int,
        queuedAt: Date
    ) {
        self.id = id
        self.seed = seed
        self.settings = settings
        self.sourceName = sourceName
        self.minimumClearanceDistance = minimumClearanceDistance
        self.currentClearanceDistance = currentClearanceDistance
        self.questionsSinceQueued = questionsSinceQueued
        self.queuedAt = queuedAt
    }
}
