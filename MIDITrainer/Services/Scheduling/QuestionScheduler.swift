import Foundation

/// The result of asking the scheduler what the next question should be.
enum NextQuestion: Equatable {
    /// Generate a fresh new question.
    case fresh
    
    /// Re-ask a previously missed sequence using the given seed and settings.
    case reask(seed: UInt64, settings: PracticeSettingsSnapshot, mistakeId: Int64)
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
    func recordCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, mistakeId: Int64?)
    
    /// The number of pending mistakes in the queue.
    var pendingCount: Int { get }
    
    /// How many fresh questions until the next re-ask is due (nil if no re-asks pending).
    var questionsUntilNextReask: Int? { get }
    
    /// Clears all pending mistakes from the queue.
    func clearQueue()
}

/// A scheduler that only generates fresh questions (no reinforcement).
final class RandomScheduler: QuestionScheduler {
    func nextQuestion(currentSettings: PracticeSettingsSnapshot) -> NextQuestion {
        .fresh
    }
    
    func recordCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, mistakeId: Int64?) {
        // Random mode doesn't track anything
    }
    
    var pendingCount: Int { 0 }
    var questionsUntilNextReask: Int? { nil }
    
    func clearQueue() {
        // Nothing to clear
    }
}
