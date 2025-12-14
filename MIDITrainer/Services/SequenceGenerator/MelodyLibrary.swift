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

    /// Returns the library for a given source type.
    static func library(for sourceType: MelodySourceType) -> MelodyPhraseLibrary {
        switch sourceType {
        case .random:
            return MelodyPhraseLibrary() // Empty, won't be used
        case .pop909:
            return pop909
        case .billboard:
            return billboard
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
}

extension MelodyPhraseLibrary {
    /// Creates a library from a dictionary (used when decoding from JSON).
    init(phrasesByLength: [Int: [MelodyPhrase]]) {
        self.phrasesByLength = phrasesByLength
    }
}
