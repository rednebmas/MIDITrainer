import Foundation

/// Loads and provides access to bundled melody phrases.
final class MelodyLibrary {
    /// POP909 pop songs library
    static let pop909: MelodyPhraseLibrary = {
        loadLibrary(named: "melody_phrases", description: "POP909")
    }()

    /// Billboard hits library
    static let billboard: MelodyPhraseLibrary = {
        loadLibrary(named: "billboard_phrases", description: "Billboard")
    }()

    /// Weimar Jazz Database library (with chord data)
    static let weimarJazz: AccompaniedPhraseLibrary = {
        loadAccompaniedLibrary(named: "weimar_jazz_phrases", description: "Weimar Jazz")
    }()

    /// Legacy shared instance (uses POP909 for backwards compatibility)
    static let shared: MelodyLibrary = {
        MelodyLibrary(library: pop909)
    }()

    let library: MelodyPhraseLibrary

    init(library: MelodyPhraseLibrary) {
        self.library = library
    }

    /// Loads a phrase library from a bundled JSON file.
    private static func loadLibrary(named name: String, description: String) -> MelodyPhraseLibrary {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            print("Warning: \(name).json not found in bundle")
            return MelodyPhraseLibrary()
        }

        do {
            let data = try Data(contentsOf: url)
            let library = try decode(data)
            print("Loaded \(library.count) \(description) melody phrases")
            return library
        } catch {
            print("Error loading \(description) phrases: \(error)")
            return MelodyPhraseLibrary()
        }
    }

    /// Loads an accompanied phrase library (with chord data) from a bundled JSON file.
    private static func loadAccompaniedLibrary(named name: String, description: String) -> AccompaniedPhraseLibrary {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            print("Warning: \(name).json not found in bundle")
            return AccompaniedPhraseLibrary()
        }

        do {
            let data = try Data(contentsOf: url)
            let library = try decodeAccompanied(data)
            print("Loaded \(library.count) \(description) melody phrases with chords")
            return library
        } catch {
            print("Error loading \(description) phrases: \(error)")
            return AccompaniedPhraseLibrary()
        }
    }

    /// Returns the library for a given source type.
    static func library(for sourceType: MelodySourceType) -> MelodyPhraseLibrary {
        switch sourceType {
        case .random:
            return MelodyPhraseLibrary() // Empty, won't be used
        case .pop909:
            return pop909
        case .billboard:
            return billboard
        case .weimarJazz:
            // Convert accompanied library to plain library (chords accessed separately)
            return weimarJazz.asMelodyPhraseLibrary()
        }
    }

    /// Returns the accompanied library for source types that have chord data.
    static func accompaniedLibrary(for sourceType: MelodySourceType) -> AccompaniedPhraseLibrary? {
        switch sourceType {
        case .weimarJazz:
            return weimarJazz
        case .billboard, .pop909, .random:
            return nil
        }
    }

    /// Decodes a phrase library from JSON data.
    /// The JSON format matches the Python script output.
    static func decode(_ data: Data) throws -> MelodyPhraseLibrary {
        // The JSON uses string keys for phrasesByLength
        struct RawLibrary: Codable {
            let phrasesByLength: [String: [RawPhrase]]
        }

        struct RawPhrase: Codable {
            let intervals: [Int]
            let durations: [Double]
            let sourceId: String?
        }

        let raw = try JSONDecoder().decode(RawLibrary.self, from: data)

        // Convert to our internal format
        var phrasesByLength: [Int: [MelodyPhrase]] = [:]

        for (lengthStr, rawPhrases) in raw.phrasesByLength {
            guard let length = Int(lengthStr) else { continue }

            let phrases = rawPhrases.compactMap { raw -> MelodyPhrase? in
                guard raw.intervals.count == raw.durations.count else { return nil }
                guard !raw.intervals.isEmpty else { return nil }
                return MelodyPhrase(
                    intervals: raw.intervals,
                    durations: raw.durations,
                    sourceId: raw.sourceId
                )
            }

            phrasesByLength[length] = phrases
        }

        return MelodyPhraseLibrary(phrasesByLength: phrasesByLength)
    }

    /// Decodes an accompanied phrase library (with chord data) from JSON data.
    static func decodeAccompanied(_ data: Data) throws -> AccompaniedPhraseLibrary {
        struct RawLibrary: Codable {
            let phrasesByLength: [String: [RawAccompaniedPhrase]]
        }

        struct RawAccompaniedPhrase: Codable {
            let intervals: [Int]
            let durations: [Double]
            let sourceId: String?
            let chords: [RawChordEvent]?
            let metadata: RawMetadata?
        }

        struct RawChordEvent: Codable {
            let offset: Double
            let chord: String
            let bass: Int?
        }

        struct RawMetadata: Codable {
            let performer: String?
            let title: String?
            let key: String?
            let startBar: Int?
        }

        let raw = try JSONDecoder().decode(RawLibrary.self, from: data)

        var phrasesByLength: [Int: [AccompaniedPhrase]] = [:]

        for (lengthStr, rawPhrases) in raw.phrasesByLength {
            guard let length = Int(lengthStr) else { continue }

            let phrases = rawPhrases.compactMap { raw -> AccompaniedPhrase? in
                guard raw.intervals.count == raw.durations.count else { return nil }
                guard !raw.intervals.isEmpty else { return nil }

                let melody = MelodyPhrase(
                    intervals: raw.intervals,
                    durations: raw.durations,
                    sourceId: raw.sourceId
                )

                let chords = (raw.chords ?? []).map { chord in
                    PhraseChordEvent(offset: chord.offset, chord: chord.chord, bass: chord.bass)
                }

                let metadata: PhraseMetadata?
                if let rawMeta = raw.metadata {
                    metadata = PhraseMetadata(
                        performer: rawMeta.performer,
                        title: rawMeta.title,
                        key: rawMeta.key,
                        startBar: rawMeta.startBar
                    )
                } else {
                    metadata = nil
                }

                return AccompaniedPhrase(melody: melody, chords: chords, metadata: metadata)
            }

            phrasesByLength[length] = phrases
        }

        return AccompaniedPhraseLibrary(phrasesByLength: phrasesByLength)
    }
}

extension MelodyPhraseLibrary {
    /// Creates a library from a dictionary (used when decoding from JSON).
    init(phrasesByLength: [Int: [MelodyPhrase]]) {
        self.phrasesByLength = phrasesByLength
    }
}

extension AccompaniedPhraseLibrary {
    /// Converts to a plain MelodyPhraseLibrary (losing chord data).
    func asMelodyPhraseLibrary() -> MelodyPhraseLibrary {
        var converted: [Int: [MelodyPhrase]] = [:]
        for (length, phrases) in phrasesByLength {
            converted[length] = phrases.map(\.melody)
        }
        return MelodyPhraseLibrary(phrasesByLength: converted)
    }
}
