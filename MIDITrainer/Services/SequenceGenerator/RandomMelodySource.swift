import Foundation

/// Generates melodies by randomly selecting scale degrees and octaves.
/// This is the original behavior of the app.
struct RandomMelodySource: MelodySource {
    func generateMelody(
        lengthRange: ClosedRange<Int>,
        scale: Scale,
        allowedDegrees: [ScaleDegree],
        allowedOctaves: [Int],
        rng: inout SeededGenerator
    ) -> MelodyGenerationResult {
        // Pick a length within the range
        let length = Int.random(in: lengthRange, using: &rng)

        var notes: [UInt8] = []
        notes.reserveCapacity(length)

        for _ in 0..<length {
            let degree = randomElement(from: allowedDegrees, using: &rng)
            let octave = randomElement(from: allowedOctaves, using: &rng)
            if let midiNote = scale.midiNoteNumber(for: degree, octave: octave) {
                notes.append(midiNote)
            }
        }

        return MelodyGenerationResult(notes: notes)
    }

    private func randomElement<T>(from array: [T], using rng: inout some RandomNumberGenerator) -> T {
        guard let element = array.randomElement(using: &rng) else {
            fatalError("randomElement called with empty array")
        }
        return element
    }
}
