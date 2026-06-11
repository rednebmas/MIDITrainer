import Foundation

/// What kind of question the completed sequence was.
enum AskedQuestion: Equatable {
    case fresh
    case reask(mistakeId: Int64)
    case fragment(fragmentId: Int64)

    var mistakeId: Int64? {
        if case .reask(let id) = self { return id }
        return nil
    }

    var fragmentId: Int64? {
        if case .fragment(let id) = self { return id }
        return nil
    }
}

/// Everything a scheduler needs to know about a completed question.
struct CompletionReport {
    let seed: UInt64?
    let settings: PracticeSettingsSnapshot
    let hadErrors: Bool
    let question: AskedQuestion
    let sourceName: String?
    /// The expected melody pitches, in order.
    let notes: [UInt8]
    /// Note indices answered incorrectly on the first guess of the first playthrough.
    let firstAttemptFailedIndices: Set<Int>

    /// Per-note first-guess results, in melody order.
    var firstGuessResults: [Bool] {
        notes.indices.map { !firstAttemptFailedIndices.contains($0) }
    }
}
