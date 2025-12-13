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
        var generator = SeededGenerator(seed: selectedSeed)

        let allowedDegrees = allowedScaleDegrees(excluding: settings.excludedDegrees)
        let allowedOctaves = settings.allowedOctaves
        let scale = Scale(key: settings.key, type: settings.scaleType)
        let rhythmPattern = rhythmLibrary.pattern(for: settings.melodyLength, rng: &generator)

        let notes = buildNotes(
            pattern: rhythmPattern,
            scale: scale,
            allowedDegrees: allowedDegrees,
            allowedOctaves: allowedOctaves,
            rng: &generator
        )

        return MelodySequence(
            notes: notes,
            key: settings.key,
            scaleType: settings.scaleType,
            excludedDegrees: settings.excludedDegrees,
            allowedOctaves: allowedOctaves,
            bpm: settings.bpm,
            seed: selectedSeed
        )
    }

    private func allowedScaleDegrees(excluding excluded: Set<ScaleDegree>) -> [ScaleDegree] {
        let degrees = ScaleDegree.allCases.filter { !excluded.contains($0) }
        return degrees.isEmpty ? ScaleDegree.allCases : degrees
    }

    private func buildNotes(
        pattern: RhythmPattern,
        scale: Scale,
        allowedDegrees: [ScaleDegree],
        allowedOctaves: [Int],
        rng: inout SeededGenerator
    ) -> [MelodyNote] {
        var notes: [MelodyNote] = []
        notes.reserveCapacity(pattern.noteCount)

        var startBeat: Double = 0
        for index in 0..<pattern.noteCount {
            let duration = pattern.durations[index]
            let degree = randomElement(from: allowedDegrees, using: &rng)
            let octave = randomElement(from: allowedOctaves, using: &rng)
            if let midiNote = scale.midiNoteNumber(for: degree, octave: octave) {
                let note = MelodyNote(
                    midiNoteNumber: midiNote,
                    startBeat: startBeat,
                    durationBeats: duration,
                    index: index
                )
                notes.append(note)
            }
            startBeat += duration
        }

        return notes
    }

    private func randomElement<T>(from array: [T], using rng: inout some RandomNumberGenerator) -> T {
        guard let element = array.randomElement(using: &rng) else {
            fatalError("randomElement called with empty array; guard this before calling")
        }
        return element
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
