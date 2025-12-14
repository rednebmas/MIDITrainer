import Foundation

/// Generates melodies by weighting interval selection based on error rates.
/// Higher error rate intervals are more likely to be selected.
struct IntervalWeightedMelodySource: MelodySource {
    /// Weights for each interval (semitones -> weight)
    private let intervalWeights: [Int: Double]
    /// Base weight for intervals with no data
    private let baseWeight: Double = 0.1

    /// Initialize with interval error rates from StatsRepository.
    /// - Parameter intervalErrorRates: Array of StatBucket with label as semitone string and rate as error rate
    init(intervalErrorRates: [StatBucket]) {
        var weights: [Int: Double] = [:]
        for bucket in intervalErrorRates {
            // Skip "Start" label (first notes have no interval)
            guard bucket.label != "Start", let interval = Int(bucket.label) else { continue }
            // Weight = error rate + base weight (so even 0% error rate gets some probability)
            weights[interval] = bucket.rate + 0.1
        }
        self.intervalWeights = weights
    }

    func generateMelody(
        lengthRange: ClosedRange<Int>,
        scale: Scale,
        allowedDegrees: [ScaleDegree],
        allowedOctaves: [Int],
        rng: inout SeededGenerator
    ) -> MelodyGenerationResult {
        let length = Int.random(in: lengthRange, using: &rng)

        var notes: [UInt8] = []
        notes.reserveCapacity(length)

        // First note: pick randomly like RandomMelodySource
        if let firstNote = randomNote(scale: scale, allowedDegrees: allowedDegrees, allowedOctaves: allowedOctaves, rng: &rng) {
            notes.append(firstNote)
        }

        // Subsequent notes: weight by interval error rate
        for _ in 1..<length {
            guard let currentNote = notes.last else { break }
            if let nextNote = selectNextNote(
                from: currentNote,
                scale: scale,
                allowedDegrees: allowedDegrees,
                allowedOctaves: allowedOctaves,
                rng: &rng
            ) {
                notes.append(nextNote)
            }
        }

        return MelodyGenerationResult(notes: notes)
    }

    /// Pick a random note (degree + octave) from allowed options
    private func randomNote(
        scale: Scale,
        allowedDegrees: [ScaleDegree],
        allowedOctaves: [Int],
        rng: inout SeededGenerator
    ) -> UInt8? {
        guard !allowedDegrees.isEmpty, !allowedOctaves.isEmpty else { return nil }

        let degree = allowedDegrees.randomElement(using: &rng)!
        let octave = allowedOctaves.randomElement(using: &rng)!
        return scale.midiNoteNumber(for: degree, octave: octave)
    }

    /// Select next note using weighted interval selection
    private func selectNextNote(
        from currentMidi: UInt8,
        scale: Scale,
        allowedDegrees: [ScaleDegree],
        allowedOctaves: [Int],
        rng: inout SeededGenerator
    ) -> UInt8? {
        // Build list of all valid next notes with their intervals and weights
        var candidates: [(midi: UInt8, weight: Double)] = []

        for degree in allowedDegrees {
            for octave in allowedOctaves {
                guard let nextMidi = scale.midiNoteNumber(for: degree, octave: octave) else { continue }

                let interval = Int(nextMidi) - Int(currentMidi)
                let weight = intervalWeights[interval] ?? baseWeight

                candidates.append((nextMidi, weight))
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Weighted random selection
        return weightedRandomElement(from: candidates, using: &rng)
    }

    /// Select an element using weighted random selection
    private func weightedRandomElement(
        from candidates: [(midi: UInt8, weight: Double)],
        using rng: inout SeededGenerator
    ) -> UInt8? {
        guard !candidates.isEmpty else { return nil }

        let totalWeight = candidates.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            // If all weights are 0, fall back to uniform random
            return candidates.randomElement(using: &rng)?.midi
        }

        var random = Double.random(in: 0..<totalWeight, using: &rng)

        for candidate in candidates {
            random -= candidate.weight
            if random <= 0 {
                return candidate.midi
            }
        }

        // Shouldn't reach here, but return last as fallback
        return candidates.last?.midi
    }
}
