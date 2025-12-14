import Foundation

/// A chord event within a melody phrase.
struct PhraseChordEvent: Codable, Equatable {
    /// Time offset in seconds from the start of the phrase.
    let offset: Double

    /// The chord symbol string (e.g., "Cmaj7", "D-7").
    let chord: String

    /// MIDI pitch of the bass note (optional, from original transcription).
    let bass: Int?

    /// Parses the chord string into a ChordSymbol.
    var chordSymbol: ChordSymbol? {
        ChordSymbol(parsing: chord)
    }
}

/// A melody phrase with associated chord data.
struct AccompaniedPhrase: Codable, Equatable {
    /// The underlying melody phrase (intervals, durations, sourceId).
    let melody: MelodyPhrase

    /// Chord events that accompany this phrase.
    let chords: [PhraseChordEvent]

    /// Metadata about the source (performer, title, key).
    let metadata: PhraseMetadata?

    /// Number of notes in the melody.
    var noteCount: Int { melody.noteCount }

    /// Creates an accompanied phrase from components.
    init(melody: MelodyPhrase, chords: [PhraseChordEvent], metadata: PhraseMetadata? = nil) {
        self.melody = melody
        self.chords = chords
        self.metadata = metadata
    }
}

/// Metadata about a phrase's source.
struct PhraseMetadata: Codable, Equatable {
    let performer: String?
    let title: String?
    let key: String?
    let startBar: Int?
}

/// A collection of accompanied phrases indexed by length.
struct AccompaniedPhraseLibrary: Codable {
    /// Phrases grouped by note count.
    let phrasesByLength: [Int: [AccompaniedPhrase]]

    /// All phrases flattened.
    var allPhrases: [AccompaniedPhrase] {
        phrasesByLength.values.flatMap { $0 }
    }

    /// Total number of phrases.
    var count: Int {
        phrasesByLength.values.reduce(0) { $0 + $1.count }
    }

    /// Returns phrases matching a length range.
    func phrases(inRange range: ClosedRange<Int>) -> [AccompaniedPhrase] {
        var result: [AccompaniedPhrase] = []
        for length in range {
            if let phrases = phrasesByLength[length] {
                result.append(contentsOf: phrases)
            }
        }
        return result
    }

    /// Creates an empty library.
    init() {
        self.phrasesByLength = [:]
    }

    /// Creates a library from a dictionary.
    init(phrasesByLength: [Int: [AccompaniedPhrase]]) {
        self.phrasesByLength = phrasesByLength
    }
}
