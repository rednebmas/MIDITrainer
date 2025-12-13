import XCTest
@testable import MIDITrainer

final class ScoringServiceTests: XCTestCase {
    private let scoring = ScoringService()

    func testScaleDegreeMapping() {
        let scale = Scale(key: Key(root: .c), type: .major)
        XCTAssertEqual(scoring.scaleDegree(for: 60, in: scale), .i) // C4
        XCTAssertEqual(scoring.scaleDegree(for: 62, in: scale), .ii) // D4
        XCTAssertNil(scoring.scaleDegree(for: 61, in: scale)) // C# not in scale
    }

    func testIntervalComputation() {
        XCTAssertNil(scoring.interval(from: nil, to: 64))
        let up = scoring.interval(from: 60, to: 67)
        XCTAssertEqual(up?.semitones, 7)
        let down = scoring.interval(from: 67, to: 60)
        XCTAssertEqual(down?.semitones, -7)
    }

    func testDescriptorForFirstAndSubsequentNotes() {
        let scale = Scale(key: Key(root: .c), type: .major)
        let firstNote = MelodyNote(midiNoteNumber: 60, startBeat: 0, durationBeats: 1, index: 0)
        let descriptorFirst = scoring.descriptor(
            expectedNote: firstNote,
            guessedMidiNote: 61,
            previousCorrectExpected: nil,
            previousCorrectGuessed: nil,
            scale: scale,
            isCorrect: false
        )

        XCTAssertNil(descriptorFirst.expectedInterval)
        XCTAssertNil(descriptorFirst.guessedInterval)
        XCTAssertEqual(descriptorFirst.noteIndexInMelody, 0)

        let secondNote = MelodyNote(midiNoteNumber: 64, startBeat: 1, durationBeats: 1, index: 1)
        let descriptorSecond = scoring.descriptor(
            expectedNote: secondNote,
            guessedMidiNote: 65,
            previousCorrectExpected: firstNote.midiNoteNumber,
            previousCorrectGuessed: firstNote.midiNoteNumber,
            scale: scale,
            isCorrect: false
        )

        XCTAssertEqual(descriptorSecond.expectedInterval?.semitones, 4) // 60 -> 64
        XCTAssertEqual(descriptorSecond.guessedInterval?.semitones, 5) // 60 -> 65
        XCTAssertEqual(descriptorSecond.noteIndexInMelody, 1)
    }
}
