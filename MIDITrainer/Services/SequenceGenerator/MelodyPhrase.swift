import Foundation

/// A melody phrase stored as intervals from the first note.
/// This allows transposition to any key by adding a root MIDI note.
struct MelodyPhrase: Codable, Equatable {
    /// Semitone intervals from the first note. First element is always 0.
    /// Example: [0, 2, 4, 2, 0] represents root, up 2, up 4, down to 2, back to root
    let intervals: [Int]

    /// Duration of each note in beats.
    /// Example: [1.0, 0.5, 0.5, 1.0, 1.0]
    let durations: [Double]

    /// Optional source identifier for attribution.
    /// Example: "pop909_001" or "bach_invention_1"
    let sourceId: String?

    /// Number of notes in this phrase.
    var noteCount: Int { intervals.count }

    /// Total duration in beats.
    var totalBeats: Double { durations.reduce(0, +) }

    init(intervals: [Int], durations: [Double], sourceId: String? = nil) {
        precondition(intervals.count == durations.count, "Intervals and durations must have same count")
        precondition(!intervals.isEmpty, "Phrase must have at least one note")
        self.intervals = intervals
        self.durations = durations
        self.sourceId = sourceId
    }

    /// Creates a phrase from absolute MIDI notes by converting to intervals.
    init(midiNotes: [UInt8], durations: [Double], sourceId: String? = nil) {
        precondition(midiNotes.count == durations.count, "Notes and durations must have same count")
        precondition(!midiNotes.isEmpty, "Phrase must have at least one note")

        let firstNote = Int(midiNotes[0])
        self.intervals = midiNotes.map { Int($0) - firstNote }
        self.durations = durations
        self.sourceId = sourceId
    }

    /// Transposes this phrase to start at a given MIDI note.
    /// - Parameter rootMidi: The MIDI note number for the first note
    /// - Returns: Array of MIDI note numbers, clamped to valid range (0-127)
    func transpose(to rootMidi: UInt8) -> [UInt8] {
        intervals.map { interval in
            let note = Int(rootMidi) + interval
            return UInt8(clamping: max(0, min(127, note)))
        }
    }

    /// Transposes to a scale degree in a given octave.
    /// - Parameters:
    ///   - scale: The scale to use
    ///   - degree: The starting scale degree
    ///   - octave: The starting octave
    /// - Returns: Array of MIDI note numbers, or nil if the root note is invalid
    func transpose(to scale: Scale, degree: ScaleDegree, octave: Int) -> [UInt8]? {
        guard let rootMidi = scale.midiNoteNumber(for: degree, octave: octave) else {
            return nil
        }
        return transpose(to: rootMidi)
    }
}

/// A collection of melody phrases indexed by length for efficient lookup.
struct MelodyPhraseLibrary: Codable {
    /// Phrases grouped by note count for efficient filtering.
    let phrasesByLength: [Int: [MelodyPhrase]]

    /// All phrases flattened.
    var allPhrases: [MelodyPhrase] {
        phrasesByLength.values.flatMap { $0 }
    }

    /// Total number of phrases in the library.
    var count: Int {
        phrasesByLength.values.reduce(0) { $0 + $1.count }
    }

    /// Returns phrases that match a length range.
    func phrases(inRange range: ClosedRange<Int>) -> [MelodyPhrase] {
        var result: [MelodyPhrase] = []
        for length in range {
            if let phrases = phrasesByLength[length] {
                result.append(contentsOf: phrases)
            }
        }
        return result
    }

    /// Creates a library from an array of phrases.
    init(phrases: [MelodyPhrase]) {
        var grouped: [Int: [MelodyPhrase]] = [:]
        for phrase in phrases {
            grouped[phrase.noteCount, default: []].append(phrase)
        }
        self.phrasesByLength = grouped
    }

    /// Creates an empty library.
    init() {
        self.phrasesByLength = [:]
    }
}
