import Foundation

/// Loads and provides access to bundled melody phrases.
final class MelodyLibrary {
    /// Shared instance using the bundled phrase library.
    static let shared: MelodyLibrary = {
        guard let url = Bundle.main.url(forResource: "melody_phrases", withExtension: "json") else {
            print("Warning: melody_phrases.json not found in bundle")
            return MelodyLibrary(library: MelodyPhraseLibrary())
        }

        do {
            let data = try Data(contentsOf: url)
            let library = try MelodyLibrary.decode(data)
            print("Loaded \(library.count) melody phrases")
            return MelodyLibrary(library: library)
        } catch {
            print("Error loading melody phrases: \(error)")
            return MelodyLibrary(library: MelodyPhraseLibrary())
        }
    }()

    let library: MelodyPhraseLibrary

    init(library: MelodyPhraseLibrary) {
        self.library = library
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
