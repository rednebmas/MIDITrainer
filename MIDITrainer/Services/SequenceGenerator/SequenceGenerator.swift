import Foundation

struct RhythmPattern: Equatable {
    let durations: [Double]

    var noteCount: Int { durations.count }
    var totalBeats: Double { durations.reduce(0, +) }
}

// Rhythm patterns are keyed by note count so the generator can always pick a pattern
// that matches the requested melody length; if none exists we fall back to an even grid.
struct RhythmLibrary {
    let patternsByCount: [Int: [RhythmPattern]]

    static let `default`: RhythmLibrary = {
        RhythmLibrary(
            patternsByCount: [
                2: [
                    RhythmPattern(durations: [2, 2]),
                    RhythmPattern(durations: [3, 1]),
                    RhythmPattern(durations: [1, 3]),
                ],
                3: [
                    RhythmPattern(durations: [1, 1, 2]),
                    RhythmPattern(durations: [1.5, 1.5, 1]),
                    RhythmPattern(durations: [4.0 / 3.0, 4.0 / 3.0, 4.0 / 3.0]), // triplet feel
                ],
                4: [
                    RhythmPattern(durations: [1, 1, 1, 1]),
                    RhythmPattern(durations: [0.5, 0.5, 1, 2]), // syncopated push on beat 2
                    RhythmPattern(durations: [0.75, 0.75, 0.5, 2]), // dotted eighth syncopation
                    RhythmPattern(durations: [0.5, 1.5, 1, 1]),
                ],
                5: [
                    RhythmPattern(durations: [1, 1, 1, 0.5, 0.5]),
                    RhythmPattern(durations: [0.5, 0.5, 0.5, 1.5, 1]),
                ],
                6: [
                    RhythmPattern(durations: [0.5, 0.5, 0.5, 0.5, 1, 1]),
                    RhythmPattern(durations: [0.75, 0.75, 0.5, 0.5, 0.75, 0.75]),
                ],
                7: [
                    RhythmPattern(durations: [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 1]),
                ],
                8: [
                    RhythmPattern(durations: Array(repeating: 0.5, count: 8)), // eighth-note grid
                    RhythmPattern(durations: [0.25, 0.75, 0.5, 0.5, 0.5, 0.75, 0.25, 0.5]), // sixteenth flavor
                ],
            ]
        )
    }()

    func patterns(for noteCount: Int) -> [RhythmPattern] {
        patternsByCount[noteCount] ?? []
    }

    func pattern(for noteCount: Int, rng: inout some RandomNumberGenerator) -> RhythmPattern {
        if let patterns = patternsByCount[noteCount], !patterns.isEmpty {
            let index = Int.random(in: 0..<patterns.count, using: &rng)
            return patterns[index]
        }

        return evenPattern(noteCount: noteCount)
    }

    func evenPattern(noteCount: Int) -> RhythmPattern {
        guard noteCount > 0 else {
            return RhythmPattern(durations: [4])
        }

        let duration = 4.0 / Double(noteCount)
        let durations = Array(repeating: duration, count: noteCount)
        return RhythmPattern(durations: durations)
    }

    var allPatterns: [RhythmPattern] {
        patternsByCount.values.flatMap { $0 }
    }
}

struct SequenceGenerator {
    private let rhythmLibrary: RhythmLibrary

    init(rhythmLibrary: RhythmLibrary = .default) {
        self.rhythmLibrary = rhythmLibrary
    }

    func generate(settings: PracticeSettingsSnapshot, seed: UInt64? = nil) -> MelodySequence {
        let selectedSeed = seed ?? UInt64.random(in: .min ... .max)
        var rng = SeededGenerator(seed: selectedSeed)

        let allowedDegrees = allowedScaleDegrees(excluding: settings.excludedDegrees)
        let allowedOctaves = settings.allowedOctaves
        let scale = Scale(key: settings.key, type: settings.scaleType)

        // Get melody source based on settings
        let melodySource: MelodySource = {
            switch settings.melodySourceType {
            case .random:
                return RandomMelodySource()
            case .pop909, .billboard:
                let library = MelodyLibrary.library(for: settings.melodySourceType)
                return RealMelodySource(library: library)
            case .weimarJazz:
                // Use AccompaniedMelodySource to include chord data
                return AccompaniedMelodySource(library: MelodyLibrary.weimarJazz)
            }
        }()

        // Use the length range for all sources
        let lengthRange = settings.melodyLengthRange

        // Generate melody using the source
        let result = melodySource.generateMelody(
            lengthRange: lengthRange,
            scale: scale,
            allowedDegrees: allowedDegrees,
            allowedOctaves: allowedOctaves,
            rng: &rng
        )

        // Get rhythm pattern for the actual note count
        let rhythmPattern = rhythmLibrary.pattern(for: result.notes.count, rng: &rng)

        // Build melody notes with timing
        let notes = buildNotesFromMidi(
            midiNotes: result.notes,
            pattern: rhythmPattern
        )

        return MelodySequence(
            notes: notes,
            key: settings.key,
            scaleType: settings.scaleType,
            excludedDegrees: settings.excludedDegrees,
            allowedOctaves: allowedOctaves,
            bpm: settings.bpm,
            seed: selectedSeed,
            sourceId: result.sourceId,
            sourceTitle: result.sourceTitle,
            chords: result.chords
        )
    }

    private func allowedScaleDegrees(excluding excluded: Set<ScaleDegree>) -> [ScaleDegree] {
        let degrees = ScaleDegree.allCases.filter { !excluded.contains($0) }
        return degrees.isEmpty ? ScaleDegree.allCases : degrees
    }

    private func buildNotesFromMidi(
        midiNotes: [UInt8],
        pattern: RhythmPattern
    ) -> [MelodyNote] {
        var notes: [MelodyNote] = []
        notes.reserveCapacity(midiNotes.count)

        var startBeat: Double = 0
        for (index, midiNote) in midiNotes.enumerated() {
            // Use pattern duration if available, otherwise use even spacing
            let duration: Double
            if index < pattern.durations.count {
                duration = pattern.durations[index]
            } else {
                duration = 4.0 / Double(midiNotes.count)
            }

            let note = MelodyNote(
                midiNoteNumber: midiNote,
                startBeat: startBeat,
                durationBeats: duration,
                index: index
            )
            notes.append(note)
            startBeat += duration
        }

        return notes
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xdeadbeef : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
