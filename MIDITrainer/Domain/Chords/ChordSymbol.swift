import Foundation

/// A chord symbol parsed from jazz notation (e.g., "Cmaj7", "D-7", "G7alt").
struct ChordSymbol: Codable, Equatable {
    /// The root note name (e.g., "C", "Db", "F#").
    let root: String

    /// The chord quality/type as a string (e.g., "maj7", "-7", "7", "dim").
    let quality: String

    /// Optional bass note for slash chords (e.g., "G" in "C/G").
    let bass: String?

    /// The original symbol string.
    let raw: String

    /// Parses a jazz chord symbol string.
    /// Examples: "Cmaj7", "D-7", "G7", "Bb6", "F#-7b5", "Ab/C"
    init?(parsing symbol: String) {
        guard !symbol.isEmpty else { return nil }
        self.raw = symbol

        var remaining = symbol[...]

        // Parse root note
        guard let firstChar = remaining.first, firstChar.isLetter else { return nil }
        var rootStr = String(firstChar)
        remaining = remaining.dropFirst()

        // Check for accidental (b or #)
        if let acc = remaining.first, acc == "b" || acc == "#" {
            rootStr.append(acc)
            remaining = remaining.dropFirst()
        }

        self.root = rootStr

        // Check for slash chord
        if let slashIdx = remaining.lastIndex(of: "/") {
            let qualityPart = remaining[..<slashIdx]
            let bassPart = remaining[remaining.index(after: slashIdx)...]
            self.quality = String(qualityPart)
            self.bass = bassPart.isEmpty ? nil : String(bassPart)
        } else {
            self.quality = String(remaining)
            self.bass = nil
        }
    }

    /// Creates a chord symbol from components.
    init(root: String, quality: String, bass: String? = nil) {
        self.root = root
        self.quality = quality
        self.bass = bass
        if let bass = bass {
            self.raw = "\(root)\(quality)/\(bass)"
        } else {
            self.raw = "\(root)\(quality)"
        }
    }

    /// Returns the semitone offset of the root from C (0-11).
    var rootSemitone: Int? {
        let noteMap: [String: Int] = [
            "C": 0, "C#": 1, "Db": 1,
            "D": 2, "D#": 3, "Eb": 3,
            "E": 4, "Fb": 4, "E#": 5,
            "F": 5, "F#": 6, "Gb": 6,
            "G": 7, "G#": 8, "Ab": 8,
            "A": 9, "A#": 10, "Bb": 10,
            "B": 11, "Cb": 11, "B#": 0
        ]
        return noteMap[root]
    }

}
