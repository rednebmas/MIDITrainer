import Foundation

/// Result of melody generation including notes and optional source info.
struct MelodyGenerationResult {
    let notes: [UInt8]
    let sourceId: String?
    let sourceTitle: String?
    let chords: [PhraseChordEvent]?

    init(notes: [UInt8], sourceId: String? = nil, sourceTitle: String? = nil, chords: [PhraseChordEvent]? = nil) {
        self.notes = notes
        self.sourceId = sourceId
        self.sourceTitle = sourceTitle
        self.chords = chords
    }
}

/// Protocol for generating melody note sequences.
/// Different implementations can produce random melodies, real song phrases, or hybrids.
protocol MelodySource {
    /// Generates MIDI note numbers for a melody.
    /// - Parameters:
    ///   - lengthRange: The acceptable range of notes (e.g., 3...6)
    ///   - scale: The scale to use for note generation
    ///   - allowedDegrees: Which scale degrees are allowed
    ///   - allowedOctaves: Which octaves the melody can span
    ///   - rng: Seeded random number generator for reproducibility
    /// - Returns: Generated notes and optional source identifier
    func generateMelody(
        lengthRange: ClosedRange<Int>,
        scale: Scale,
        allowedDegrees: [ScaleDegree],
        allowedOctaves: [Int],
        rng: inout SeededGenerator
    ) -> MelodyGenerationResult
}

/// Identifies which melody source to use
enum MelodySourceType: String, CaseIterable, Codable {
    case billboard = "Billboard Hits"
    case pop909 = "Pop (POP909)"
    case weimarJazz = "Jazz Solos (Weimar)"
    case random = "Random"

    var displayName: String { rawValue }

    var isRealMelody: Bool {
        switch self {
        case .random: return false
        case .pop909, .billboard, .weimarJazz: return true
        }
    }

    /// Whether this source has chord accompaniment data.
    var hasChords: Bool {
        switch self {
        case .weimarJazz: return true
        case .billboard, .pop909, .random: return false
        }
    }
}
