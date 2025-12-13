import XCTest
@testable import MIDITrainer

final class SequenceGeneratorTests: XCTestCase {
    func testGenerationIsDeterministicWithSeed() {
        let settings = PracticeSettingsSnapshot(
            key: Key(root: .c),
            scaleType: .major,
            excludedDegrees: [],
            allowedOctaves: [4],
            melodyLength: 5,
            bpm: 90
        )
        let generator = SequenceGenerator()
        let seed: UInt64 = 42

        let first = generator.generate(settings: settings, seed: seed)
        let second = generator.generate(settings: settings, seed: seed)

        XCTAssertEqual(first.notes.count, settings.melodyLength)
        XCTAssertEqual(first.notes, second.notes)
        XCTAssertEqual(first.seed, second.seed)

        var expectedStart: Double = 0
        for note in first.notes {
            XCTAssertEqual(note.startBeat, expectedStart, accuracy: 0.0001)
            expectedStart += note.durationBeats
        }
        XCTAssertEqual(expectedStart, 4.0, accuracy: 0.0001)

        let scale = Scale(key: settings.key, type: settings.scaleType)
        let allowedNotes = Set(ScaleDegree.allCases.compactMap { scale.midiNoteNumber(for: $0, octave: 4) })
        for note in first.notes {
            XCTAssertTrue(allowedNotes.contains(note.midiNoteNumber))
        }
    }
}
