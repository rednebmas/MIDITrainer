import XCTest
@testable import MIDITrainer

final class RhythmLibraryTests: XCTestCase {
    func testPatternsSumToFourBeats() {
        let library = RhythmLibrary.default
        let tolerance = 0.0001

        for pattern in library.allPatterns {
            XCTAssertEqual(pattern.totalBeats, 4.0, accuracy: tolerance)
        }

        let fallback = library.evenPattern(noteCount: 5)
        XCTAssertEqual(fallback.totalBeats, 4.0, accuracy: tolerance)
        XCTAssertEqual(fallback.noteCount, 5)
    }
}
