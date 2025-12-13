import Foundation

/// Represents a sequence that was answered incorrectly and is queued for re-asking.
struct QueuedMistake: Equatable, Codable {
    /// Unique identifier for this queued entry (database row ID).
    let id: Int64
    
    /// The seed used to regenerate the exact same sequence.
    let seed: UInt64
    
    /// The settings snapshot used to generate the sequence (captured at queue time).
    let settings: PracticeSettingsSnapshot
    
    /// The minimum number of fresh questions required before this can be re-asked.
    var clearanceDistance: Int
    
    /// How many fresh questions have been answered since this was queued or last attempted.
    var questionsSinceQueued: Int
    
    /// Whether this mistake is due to be re-asked (has waited enough fresh questions).
    var isDue: Bool {
        questionsSinceQueued >= clearanceDistance
    }
    
    /// The timestamp when this mistake was first queued.
    let queuedAt: Date
    
    /// Creates a new queued mistake with default initial values.
    init(id: Int64, seed: UInt64, settings: PracticeSettingsSnapshot, queuedAt: Date = Date()) {
        self.id = id
        self.seed = seed
        self.settings = settings
        self.clearanceDistance = 1
        self.questionsSinceQueued = 0
        self.queuedAt = queuedAt
    }
    
    /// Creates a queued mistake with all values specified (for loading from persistence).
    init(
        id: Int64,
        seed: UInt64,
        settings: PracticeSettingsSnapshot,
        clearanceDistance: Int,
        questionsSinceQueued: Int,
        queuedAt: Date
    ) {
        self.id = id
        self.seed = seed
        self.settings = settings
        self.clearanceDistance = clearanceDistance
        self.questionsSinceQueued = questionsSinceQueued
        self.queuedAt = queuedAt
    }
}
