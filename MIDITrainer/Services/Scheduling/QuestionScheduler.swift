import Foundation

/// The result of asking the scheduler what the next question should be.
enum NextQuestion: Equatable {
    /// Generate a fresh new question. A non-nil seed pins the melody (used by
    /// adaptive mode to serve a difficulty-targeted candidate).
    case fresh(seed: UInt64?)

    /// Re-ask a previously missed sequence using the given seed and settings.
    case reask(seed: UInt64, settings: PracticeSettingsSnapshot, mistakeId: Int64)

    /// Drill a 2-note fragment extracted from a failed melody.
    case fragment(FragmentDrill)
}

/// A resolved 2-note drill ready to play: actual pitches in the current key
/// plus a display label like "↑P4 drill from Dark Horse".
struct FragmentDrill: Equatable {
    let fragmentId: Int64
    let midiNotes: [UInt8]
    let label: String
}

/// Protocol for question scheduling strategies.
/// Implementations decide whether to present a fresh question or a queued mistake.
protocol QuestionScheduler: AnyObject {
    /// Returns the next question to present.
    func nextQuestion(currentSettings: PracticeSettingsSnapshot) -> NextQuestion
    
    /// Called when a sequence is completed with the result.
    /// - Parameters:
    ///   - seed: The seed that was used for the sequence.
    ///   - settings: The settings used to generate the sequence.
    ///   - hadErrors: Whether any errors were made during the attempt.
    ///   - mistakeId: If this was a re-ask, the ID of the mistake entry (nil for fresh questions).
    ///   - sourceName: Human-readable name of the melody source (e.g., "Art Pepper - Anthropology").
    func recordCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, mistakeId: Int64?, sourceName: String?)
    
    /// The number of pending mistakes in the queue.
    var pendingCount: Int { get }
    
    /// How many fresh questions until the next re-ask is due (nil if no re-asks pending).
    var questionsUntilNextReask: Int? { get }
    
    /// Snapshot of the current queue (if any) for debugging/inspection.
    var queueSnapshot: [QueuedMistake] { get }

    /// Clears all pending mistakes from the queue.
    func clearQueue()

    /// Re-reads persisted queue state. Called when this scheduler becomes
    /// active, since other schedulers may have mutated the shared tables.
    func reload()
}

extension QuestionScheduler {
    func reload() {}
}

/// A scheduler that only generates fresh questions (no reinforcement).
final class RandomScheduler: QuestionScheduler {
    func nextQuestion(currentSettings: PracticeSettingsSnapshot) -> NextQuestion {
        .fresh(seed: nil)
    }
    
    func recordCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, mistakeId: Int64?, sourceName: String?) {
        // Random mode doesn't track anything
    }
    
    var pendingCount: Int { 0 }
    var questionsUntilNextReask: Int? { nil }
    var queueSnapshot: [QueuedMistake] { [] }
    
    func clearQueue() {
        // Nothing to clear
    }
}
