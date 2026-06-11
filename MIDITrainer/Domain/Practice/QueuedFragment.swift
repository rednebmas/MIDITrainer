import Foundation

/// Identity used to deduplicate fragments: the same degree transition is one
/// skill, regardless of which melody it came from. Octave participates only
/// when octave-sensitive grading is on.
struct FragmentIdentity: Hashable {
    let fromDegree: ScaleDegree
    let toDegree: ScaleDegree
    let intervalSemitones: Int
    let fromOctave: Int?
}

/// A queued 2-note drill extracted from a failed melody, stored key-relative
/// (degree + octave) so it transposes with the user's current key.
struct QueuedFragment: Equatable, Identifiable {
    let id: Int64
    let parentMistakeId: Int64?
    let fromDegree: ScaleDegree
    let fromOctave: Int
    let toDegree: ScaleDegree
    let toOctave: Int
    let intervalSemitones: Int
    let sourceName: String?
    var consecutiveCorrect: Int
    var questionsSinceAsked: Int
    var totalFailures: Int
    let queuedAt: Date

    var isDue: Bool { questionsSinceAsked >= AdaptiveTuning.fragmentSpacing }

    func identity(octaveMatters: Bool) -> FragmentIdentity {
        FragmentIdentity(
            fromDegree: fromDegree,
            toDegree: toDegree,
            intervalSemitones: intervalSemitones,
            fromOctave: octaveMatters ? fromOctave : nil
        )
    }
}
