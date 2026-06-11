import Foundation

/// A key-relative 2-note transition lifted from a failed melody.
struct ExtractedFragment: Equatable {
    let fromDegree: ScaleDegree
    let fromOctave: Int
    let toDegree: ScaleDegree
    let toOctave: Int
    let intervalSemitones: Int

    func identity(octaveMatters: Bool) -> FragmentIdentity {
        FragmentIdentity(
            fromDegree: fromDegree,
            toDegree: toDegree,
            intervalSemitones: intervalSemitones,
            fromOctave: octaveMatters ? fromOctave : nil
        )
    }
}

/// Turns a failed melody into drillable fragments: for each note missed on
/// the first guess (index ≥ 1), the transition from the previous note.
/// Index-0 failures have no incoming interval and yield nothing.
struct FragmentExtractor {
    private let scoringService = ScoringService()

    func extract(notes: [UInt8], failedIndices: Set<Int>, scale: Scale) -> [ExtractedFragment] {
        failedIndices.sorted().compactMap { index in
            guard index >= 1, index < notes.count else { return nil }
            return fragment(from: notes[index - 1], to: notes[index], scale: scale)
        }
    }

    private func fragment(from: UInt8, to: UInt8, scale: Scale) -> ExtractedFragment? {
        guard let fromPosition = degreePosition(of: from, in: scale),
              let toPosition = degreePosition(of: to, in: scale) else { return nil }
        return ExtractedFragment(
            fromDegree: fromPosition.degree,
            fromOctave: fromPosition.octave,
            toDegree: toPosition.degree,
            toOctave: toPosition.octave,
            intervalSemitones: Int(to) - Int(from)
        )
    }

    private func degreePosition(of midi: UInt8, in scale: Scale) -> (degree: ScaleDegree, octave: Int)? {
        guard let degree = scoringService.scaleDegree(for: midi, in: scale),
              let offset = scale.semitoneOffset(for: degree) else { return nil }
        let octave = (Int(midi) - scale.key.root.rawValue - offset) / 12 - 1
        guard scale.midiNoteNumber(for: degree, octave: octave) == midi else { return nil }
        return (degree, octave)
    }
}
