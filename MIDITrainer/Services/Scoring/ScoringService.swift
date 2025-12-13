import Foundation

struct ScoringService {
    func scaleDegree(for midiNote: UInt8, in scale: Scale) -> ScaleDegree? {
        let semitoneFromRoot = (Int(midiNote) - scale.key.root.rawValue).positiveModulo(12)
        guard let index = scale.type.semitoneOffsets.firstIndex(of: semitoneFromRoot) else {
            return nil
        }
        return ScaleDegree.allCases[index]
    }

    func interval(from previous: UInt8?, to current: UInt8) -> Interval? {
        guard let previous else { return nil }
        return Interval(semitones: Int(current) - Int(previous))
    }

    func descriptor(
        expectedNote: MelodyNote,
        guessedMidiNote: UInt8,
        previousCorrectExpected: UInt8?,
        previousCorrectGuessed: UInt8?,
        scale: Scale,
        isCorrect: Bool
    ) -> AttemptMetadata {
        AttemptMetadata(
            expectedMidiNoteNumber: expectedNote.midiNoteNumber,
            guessedMidiNoteNumber: guessedMidiNote,
            expectedScaleDegree: scaleDegree(for: expectedNote.midiNoteNumber, in: scale),
            guessedScaleDegree: scaleDegree(for: guessedMidiNote, in: scale),
            expectedInterval: interval(from: previousCorrectExpected, to: expectedNote.midiNoteNumber),
            guessedInterval: interval(from: previousCorrectGuessed, to: guessedMidiNote),
            noteIndexInMelody: expectedNote.index,
            isCorrect: isCorrect,
            timestamp: Date()
        )
    }
}

private extension Int {
    func positiveModulo(_ modulus: Int) -> Int {
        let result = self % modulus
        return result >= 0 ? result : result + modulus
    }
}
