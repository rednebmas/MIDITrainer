import Foundation

/// Result of melody generation including notes and optional source info.
struct MelodyGenerationResult {
    let notes: [UInt8]
    let sourceId: String?

    init(notes: [UInt8], sourceId: String? = nil) {
        self.notes = notes
        self.sourceId = sourceId
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
    case random = "Random"
    case pop909 = "Pop (POP909)"
    case billboard = "Billboard Hits"

    var displayName: String { rawValue }

    var isRealMelody: Bool {
        switch self {
        case .random: return false
        case .pop909, .billboard: return true
        }
    }
}
