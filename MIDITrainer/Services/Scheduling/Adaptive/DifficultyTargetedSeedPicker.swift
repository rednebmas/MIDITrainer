import Foundation

/// Picks a generation seed whose melody best matches the difficulty dial.
///
/// Candidate seeds are derived deterministically from a master seed, each
/// candidate melody is scored by the predictor, and the closest one wins.
/// The chosen seed regenerates the identical melody later through the
/// standard re-ask path.
struct DifficultyTargetedSeedPicker {
    private let generator: SequenceGenerator

    init(generator: SequenceGenerator = SequenceGenerator()) {
        self.generator = generator
    }

    func pickSeed(
        settings: PracticeSettingsSnapshot,
        dial: Double,
        predictor: MelodyAccuracyPredictor,
        masterSeed: UInt64
    ) -> UInt64 {
        var rng = SeededGenerator(seed: masterSeed)
        var bestSeed = masterSeed
        var bestDistance = Double.infinity
        for _ in 0..<AdaptiveTuning.candidateCount {
            let candidate = rng.next()
            let melody = generator.generate(settings: settings, seed: candidate)
            let predicted = predictor.predict(notes: melody.notes.map(\.midiNoteNumber))
            let distance = abs(predicted - dial)
            if distance < bestDistance {
                bestSeed = candidate
                bestDistance = distance
            }
        }
        return bestSeed
    }
}
