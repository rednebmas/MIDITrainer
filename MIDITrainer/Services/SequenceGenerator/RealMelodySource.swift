import Foundation

/// Generates melodies by selecting real phrases from a library and transposing them.
struct RealMelodySource: MelodySource {
    private let library: MelodyPhraseLibrary

    init(library: MelodyPhraseLibrary) {
        self.library = library
    }

    func generateMelody(
        lengthRange: ClosedRange<Int>,
        scale: Scale,
        allowedDegrees: [ScaleDegree],
        allowedOctaves: [Int],
        rng: inout SeededGenerator
    ) -> MelodyGenerationResult {
        // Get all phrases that match the length range
        let matchingPhrases = library.phrases(inRange: lengthRange)

        guard !matchingPhrases.isEmpty else {
            return RandomMelodySource().generateMelody(
                lengthRange: lengthRange,
                scale: scale,
                allowedDegrees: allowedDegrees,
                allowedOctaves: allowedOctaves,
                rng: &rng
            )
        }

        // Shuffle phrases deterministically and try to find one that fits
        var shuffledIndices = Array(0..<matchingPhrases.count)
        shuffledIndices.shuffle(using: &rng)

        // Try each phrase until we find one that works with allowed degrees
        for phraseIndex in shuffledIndices {
            let phrase = matchingPhrases[phraseIndex]

            // Try each allowed starting degree
            var startingDegrees = allowedDegrees
            startingDegrees.shuffle(using: &rng)

            for startDegree in startingDegrees {
                // Check if this phrase fits with this starting degree
                if let mappedNotes = mapPhraseToScale(
                    phrase: phrase,
                    scale: scale,
                    startDegree: startDegree,
                    allowedDegrees: Set(allowedDegrees),
                    allowedOctaves: allowedOctaves,
                    rng: &rng
                ) {
                    return MelodyGenerationResult(
                        notes: mappedNotes,
                        sourceId: phrase.sourceId
                    )
                }
            }
        }

        // No phrase fits the constraints, fall back to random
        return RandomMelodySource().generateMelody(
            lengthRange: lengthRange,
            scale: scale,
            allowedDegrees: allowedDegrees,
            allowedOctaves: allowedOctaves,
            rng: &rng
        )
    }

    /// Maps a phrase to scale degrees, returning nil if any note doesn't land exactly on an allowed degree
    /// or if the phrase doesn't fit within the allowed octaves.
    private func mapPhraseToScale(
        phrase: MelodyPhrase,
        scale: Scale,
        startDegree: ScaleDegree,
        allowedDegrees: Set<ScaleDegree>,
        allowedOctaves: [Int],
        rng: inout SeededGenerator
    ) -> [UInt8]? {
        guard !allowedOctaves.isEmpty else { return nil }

        let scaleOffsets = scale.type.semitoneOffsets
        let startOffset = scale.semitoneOffset(for: startDegree) ?? 0

        // First pass: validate all notes land on allowed scale degrees and calculate octave shifts
        var degreeAndOctaveShifts: [(degree: ScaleDegree, octaveShift: Int)] = []

        for interval in phrase.intervals {
            // Calculate the target semitone offset from root
            let totalSemitones = startOffset + interval
            var targetSemitone = totalSemitones % 12
            if targetSemitone < 0 { targetSemitone += 12 }

            // Find the exact scale degree (no snapping!)
            guard let degree = findExactScaleDegree(
                targetSemitone: targetSemitone,
                scaleOffsets: scaleOffsets
            ) else {
                // Chromatic note - reject phrase
                return nil
            }

            // Check if this degree is allowed
            guard allowedDegrees.contains(degree) else {
                return nil
            }

            // Calculate octave shift from the starting note
            let octaveShift: Int
            if totalSemitones >= 0 {
                octaveShift = totalSemitones / 12
            } else {
                octaveShift = (totalSemitones - 11) / 12
            }

            degreeAndOctaveShifts.append((degree, octaveShift))
        }

        // Find the range of octave shifts in the phrase
        let minShift = degreeAndOctaveShifts.map(\.octaveShift).min() ?? 0
        let maxShift = degreeAndOctaveShifts.map(\.octaveShift).max() ?? 0
        let phraseOctaveSpan = maxShift - minShift

        // Find valid starting octaves where the entire phrase fits
        let minAllowedOctave = allowedOctaves.min()!
        let maxAllowedOctave = allowedOctaves.max()!
        let allowedOctaveSpan = maxAllowedOctave - minAllowedOctave

        // The phrase must fit within the allowed octave range
        guard phraseOctaveSpan <= allowedOctaveSpan else {
            return nil
        }

        // Find all valid starting octaves
        var validStartOctaves: [Int] = []
        for startOctave in allowedOctaves {
            let lowestOctave = startOctave + minShift
            let highestOctave = startOctave + maxShift
            if lowestOctave >= minAllowedOctave && highestOctave <= maxAllowedOctave {
                validStartOctaves.append(startOctave)
            }
        }

        guard !validStartOctaves.isEmpty else {
            return nil
        }

        // Pick a random valid starting octave
        let startOctave = randomElement(from: validStartOctaves, using: &rng)

        // Build the final MIDI notes
        var result: [UInt8] = []
        result.reserveCapacity(degreeAndOctaveShifts.count)

        for (degree, octaveShift) in degreeAndOctaveShifts {
            let targetOctave = startOctave + octaveShift
            guard let midiNote = scale.midiNoteNumber(for: degree, octave: targetOctave) else {
                return nil
            }
            result.append(midiNote)
        }

        return result
    }

    /// Finds the exact scale degree for a semitone offset, or nil if it's chromatic.
    private func findExactScaleDegree(
        targetSemitone: Int,
        scaleOffsets: [Int]
    ) -> ScaleDegree? {
        // Check if target matches the octave (degree viii)
        if targetSemitone == 0 {
            // Could be degree i or viii depending on context, but for matching we use i
            return .i
        }

        // Check each scale degree
        for (index, offset) in scaleOffsets.enumerated() {
            if offset == targetSemitone && index < ScaleDegree.allCases.count {
                return ScaleDegree.allCases[index]
            }
        }

        // No exact match - this is a chromatic note
        return nil
    }

    private func randomElement<T>(from array: [T], using rng: inout some RandomNumberGenerator) -> T {
        guard let element = array.randomElement(using: &rng) else {
            fatalError("randomElement called with empty array")
        }
        return element
    }
}
