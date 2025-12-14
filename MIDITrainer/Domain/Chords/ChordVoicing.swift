import Foundation

/// Defines how a chord should be voiced (which notes to play).
enum ChordVoicingStyle: String, CaseIterable, Codable {
    /// Root + 3rd + 7th (default jazz voicing)
    case shell = "Shell (Root + 3rd + 7th)"

    /// Root + 3rd + 5th + 7th
    case full = "Full (Root + 3rd + 5th + 7th)"

    /// Just root + 5th (power chord style)
    case rootFifth = "Root + 5th"

    /// Root only (for bass accompaniment)
    case rootOnly = "Root Only"

    var displayName: String { rawValue }
}

/// Generates MIDI note numbers for chord voicings.
struct ChordVoicer {
    let style: ChordVoicingStyle
    let octave: Int

    init(style: ChordVoicingStyle = .shell, octave: Int = 3) {
        self.style = style
        self.octave = octave
    }

    /// Generates MIDI note numbers for a chord symbol.
    /// - Parameters:
    ///   - chord: The chord symbol to voice
    ///   - transposition: Semitones to transpose (for key matching)
    /// - Returns: Array of MIDI note numbers, or nil if chord can't be parsed
    func voicing(for chord: ChordSymbol, transposition: Int = 0) -> [UInt8]? {
        guard let rootSemi = chord.rootSemitone else { return nil }

        let transposedRoot = (rootSemi + transposition + 120) % 12
        let rootMidi = 12 * (octave + 1) + transposedRoot

        let intervals = intervals(for: chord)

        return intervals.map { interval in
            UInt8(clamping: rootMidi + interval)
        }
    }

    /// Returns the intervals to play based on voicing style and chord quality.
    private func intervals(for chord: ChordSymbol) -> [Int] {
        let quality = chord.quality.lowercased()

        // Determine chord tones
        let third = isMinor(quality) ? 3 : 4
        let fifth = isFlatFive(quality) ? 6 : (isAugmented(quality) ? 8 : 7)
        let seventh = seventhInterval(for: quality)

        switch style {
        case .rootOnly:
            return [0]

        case .rootFifth:
            return [0, fifth]

        case .shell:
            // Root + 3rd + 7th (skip 5th for clarity)
            if let sev = seventh {
                return [0, third, sev]
            } else {
                // No 7th, use root + 3rd + 5th
                return [0, third, fifth]
            }

        case .full:
            if let sev = seventh {
                return [0, third, fifth, sev]
            } else {
                return [0, third, fifth]
            }
        }
    }

    private func isMinor(_ quality: String) -> Bool {
        quality.hasPrefix("-") ||
        quality.hasPrefix("m") && !quality.hasPrefix("maj") ||
        quality.contains("dim") ||
        quality.contains("o")
    }

    private func isAugmented(_ quality: String) -> Bool {
        quality.hasPrefix("+") || quality.contains("aug")
    }

    private func isFlatFive(_ quality: String) -> Bool {
        quality.contains("b5") || quality.contains("dim") || quality.contains("o")
    }

    private func seventhInterval(for quality: String) -> Int? {
        if quality.contains("j7") || quality.contains("maj7") {
            return 11 // Major 7th
        } else if quality.contains("dim7") || quality.contains("o7") {
            return 9 // Diminished 7th
        } else if quality.contains("7") {
            return 10 // Dominant 7th
        } else if quality.contains("6") {
            return 9 // 6th (like dim 7th interval)
        }
        return nil // No 7th
    }
}
