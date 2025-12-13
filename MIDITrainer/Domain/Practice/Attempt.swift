import Foundation

struct AttemptMetadata: Equatable {
    let expectedMidiNoteNumber: UInt8
    let guessedMidiNoteNumber: UInt8
    let expectedScaleDegree: ScaleDegree?
    let guessedScaleDegree: ScaleDegree?
    let expectedInterval: Interval?
    let guessedInterval: Interval?
    let noteIndexInMelody: Int
    let isCorrect: Bool
    let timestamp: Date
}
