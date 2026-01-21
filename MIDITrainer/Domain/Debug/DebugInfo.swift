import Foundation

struct DebugInfo {
    let questionState: QuestionState
    let settingsContext: SettingsContext
    let recentAttempts: [AttemptEntry]
    let sequenceInfo: SequenceInfo?

    struct QuestionState {
        let noteIndex: Int?
        let totalNotes: Int
        let expectedMidiNote: UInt8?
        let isOctaveSensitive: Bool
    }

    struct SettingsContext {
        let keyName: String
        let scaleName: String
        let allowedOctaves: [Int]
        let octaveMatters: Bool
        let useOnScreenKeyboard: Bool
    }

    struct AttemptEntry {
        let playedNote: UInt8
        let expectedNote: UInt8
        let isCorrect: Bool
    }

    struct SequenceInfo {
        let seedOrName: String
        let midiNotes: [UInt8]
    }

    var formatted: String {
        var lines: [String] = []
        lines.append("=== MIDITrainer Debug ===")
        lines.append(contentsOf: formattedQuestionState)
        lines.append("")
        lines.append(contentsOf: formattedSettings)
        lines.append("")
        lines.append(contentsOf: formattedAttempts)
        lines.append("")
        lines.append(contentsOf: formattedSequence)
        return lines.joined(separator: "\n")
    }

    private var formattedQuestionState: [String] {
        var lines: [String] = []
        let noteDisplay = (questionState.noteIndex ?? questionState.totalNotes) + 1
        lines.append("Question: Note \(noteDisplay) of \(questionState.totalNotes)")

        if let expected = questionState.expectedMidiNote {
            lines.append("Expected: \(expected) (\(midiNoteName(expected)))")
        } else {
            lines.append("Expected: (sequence complete)")
        }

        lines.append("Octave sensitive: \(questionState.isOctaveSensitive ? "yes" : "no")")
        return lines
    }

    private var formattedSettings: [String] {
        [
            "Settings:",
            "- Key: \(settingsContext.keyName) \(settingsContext.scaleName)",
            "- Octaves: \(settingsContext.allowedOctaves)",
            "- Octave matters: \(settingsContext.octaveMatters)",
            "- On-screen keyboard: \(settingsContext.useOnScreenKeyboard ? "yes" : "no")"
        ]
    }

    private var formattedAttempts: [String] {
        guard !recentAttempts.isEmpty else {
            return ["Recent attempts: none"]
        }

        var lines = ["Recent attempts on this note:"]
        for attempt in recentAttempts.suffix(5) {
            let played = "\(attempt.playedNote) (\(midiNoteName(attempt.playedNote)))"
            let expected = "\(attempt.expectedNote) (\(midiNoteName(attempt.expectedNote)))"
            let result = attempt.isCorrect ? "correct" : "wrong"
            lines.append("- Played \(played), expected \(expected) → \(result)")
        }
        return lines
    }

    private var formattedSequence: [String] {
        guard let info = sequenceInfo else {
            return ["Sequence: none"]
        }

        let notesList = info.midiNotes.map { "\($0) (\(midiNoteName($0)))" }
        return [
            "Sequence (seed \(info.seedOrName)):",
            "[\(notesList.joined(separator: ", "))]"
        ]
    }

    private func midiNoteName(_ note: UInt8) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = Int(note) / 12 - 1
        return "\(noteNames[Int(note) % 12])\(octave)"
    }
}
