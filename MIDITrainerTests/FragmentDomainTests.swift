import XCTest
@testable import MIDITrainer

final class FragmentExtractorTests: XCTestCase {
    private let extractor = FragmentExtractor()
    private let cMajor = Scale(key: Key(root: .c), type: .major)

    func testExtractsTransitionIntoEachFailedNote() {
        // C4 E4 G4 C5; failed the E (index 1) and the C5 (index 3)
        let fragments = extractor.extract(notes: [60, 64, 67, 72], failedIndices: [1, 3], scale: cMajor)
        XCTAssertEqual(fragments, [
            ExtractedFragment(fromDegree: .i, fromOctave: 4, toDegree: .iii, toOctave: 4, intervalSemitones: 4),
            ExtractedFragment(fromDegree: .v, fromOctave: 4, toDegree: .i, toOctave: 5, intervalSemitones: 5),
        ])
    }

    func testIndexZeroFailureYieldsNothing() {
        XCTAssertEqual(extractor.extract(notes: [60, 64], failedIndices: [0], scale: cMajor), [])
    }

    func testChromaticNoteYieldsNothing() {
        // F#4 (66) is not in C major
        XCTAssertEqual(extractor.extract(notes: [60, 66], failedIndices: [1], scale: cMajor), [])
    }

    func testOctaveRoundTripsForWrappingRoots() {
        // A major: A4 (69) up a major third to C#5 (73). Naive midi/12
        // octave math would break this; the stored pair must re-render to 73.
        let aMajor = Scale(key: Key(root: .a), type: .major)
        let fragments = extractor.extract(notes: [69, 73], failedIndices: [1], scale: aMajor)
        XCTAssertEqual(fragments.count, 1)
        let f = fragments[0]
        XCTAssertEqual(aMajor.midiNoteNumber(for: f.fromDegree, octave: f.fromOctave), 69)
        XCTAssertEqual(aMajor.midiNoteNumber(for: f.toDegree, octave: f.toOctave), 73)
    }
}

final class FragmentIdentityTests: XCTestCase {
    private let fragment = ExtractedFragment(
        fromDegree: .v, fromOctave: 4, toDegree: .i, toOctave: 5, intervalSemitones: 5
    )

    func testOctaveIgnoredWhenOctaveDoesNotMatter() {
        let other = ExtractedFragment(
            fromDegree: .v, fromOctave: 3, toDegree: .i, toOctave: 4, intervalSemitones: 5
        )
        XCTAssertEqual(fragment.identity(octaveMatters: false), other.identity(octaveMatters: false))
        XCTAssertNotEqual(fragment.identity(octaveMatters: true), other.identity(octaveMatters: true))
    }

    func testDirectionDistinguishesIdentities() {
        let descending = ExtractedFragment(
            fromDegree: .v, fromOctave: 4, toDegree: .i, toOctave: 4, intervalSemitones: -7
        )
        XCTAssertNotEqual(fragment.identity(octaveMatters: false), descending.identity(octaveMatters: false))
    }
}

final class IntervalNameTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(IntervalName.label(semitones: 0), "U")
        XCTAssertEqual(IntervalName.label(semitones: 5), "↑P4")
        XCTAssertEqual(IntervalName.label(semitones: -4), "↓M3")
        XCTAssertEqual(IntervalName.label(semitones: 12), "↑8ve")
        XCTAssertEqual(IntervalName.label(semitones: -14), "↓14st")
    }
}
