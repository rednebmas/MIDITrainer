import XCTest
@testable import MIDITrainer

final class StatsRepositoryAdaptiveTests: XCTestCase {
    private var db: Database!
    private var stats: StatsRepository!
    private var attempts: AttemptRepository!
    private var nextMelodyNoteId: Int64 = 0

    override func setUp() {
        super.setUp()
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).sqlite"
        db = try! Database(path: path)
        stats = StatsRepository(db: db)
        attempts = AttemptRepository(db: db)
    }

    private func insertNote(
        interval: Int?,
        guesses: [Bool],
        key: Key = Key(root: .c),
        timestamp: Date = Date()
    ) {
        nextMelodyNoteId += 1
        for (offset, isCorrect) in guesses.enumerated() {
            let metadata = AttemptMetadata(
                expectedMidiNoteNumber: 60,
                guessedMidiNoteNumber: isCorrect ? 60 : 61,
                expectedScaleDegree: nil,
                guessedScaleDegree: nil,
                expectedInterval: interval.map { Interval(semitones: $0) },
                guessedInterval: nil,
                noteIndexInMelody: 0,
                isCorrect: isCorrect,
                timestamp: timestamp.addingTimeInterval(Double(offset))
            )
            try! attempts.insertAttempt(
                metadata: metadata,
                sessionId: 1,
                sequenceId: 1,
                melodyNoteId: nextMelodyNoteId,
                key: key,
                scaleType: .major
            )
        }
    }

    func testFirstGuessOnlyCountsFirstAttemptPerNote() throws {
        insertNote(interval: 5, guesses: [false, false, true])
        insertNote(interval: 5, guesses: [true])

        let result = try stats.firstGuessAccuracyByInterval(filter: .allKeys)
        XCTAssertEqual(result.intervals, [IntervalAccuracy(semitones: 5, successCount: 1, total: 2)])
    }

    func testStartBucketSeparatedFromIntervals() throws {
        insertNote(interval: nil, guesses: [true])
        insertNote(interval: 2, guesses: [false])

        let result = try stats.firstGuessAccuracyByInterval(filter: .allKeys)
        XCTAssertEqual(result.start, IntervalAccuracy(semitones: -9999, successCount: 1, total: 1))
        XCTAssertEqual(result.intervals, [IntervalAccuracy(semitones: 2, successCount: 0, total: 1)])
        XCTAssertEqual(result.totalAttempts, 2)
    }

    func testSinceExcludesOldAttempts() throws {
        insertNote(interval: 3, guesses: [false], timestamp: Date(timeIntervalSinceNow: -1000))
        insertNote(interval: 3, guesses: [true], timestamp: Date())

        let result = try stats.firstGuessAccuracyByInterval(
            filter: .allKeys, since: Date(timeIntervalSinceNow: -500)
        )
        XCTAssertEqual(result.intervals, [IntervalAccuracy(semitones: 3, successCount: 1, total: 1)])
    }

    func testKeyFilterRestrictsRows() throws {
        insertNote(interval: 4, guesses: [true], key: Key(root: .c))
        insertNote(interval: 4, guesses: [false], key: Key(root: .d))

        let result = try stats.firstGuessAccuracyByInterval(filter: .key(Key(root: .d), .major))
        XCTAssertEqual(result.intervals, [IntervalAccuracy(semitones: 4, successCount: 0, total: 1)])
    }

    func testRecentFirstGuessResultsChronologicalAndLimited() throws {
        let base = Date(timeIntervalSinceNow: -100)
        insertNote(interval: 1, guesses: [true], timestamp: base)
        insertNote(interval: 1, guesses: [false, true], timestamp: base.addingTimeInterval(10))
        insertNote(interval: 1, guesses: [true], timestamp: base.addingTimeInterval(20))

        XCTAssertEqual(try stats.recentFirstGuessResults(filter: .allKeys, limit: 10), [true, false, true])
        XCTAssertEqual(try stats.recentFirstGuessResults(filter: .allKeys, limit: 2), [false, true])
    }
}
