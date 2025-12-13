import XCTest
@testable import MIDITrainer

final class StatsRepositoryTests: XCTestCase {
    func testDegreeIntervalAndIndexAggregations() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let db = try Database(path: tempURL.path)

        let settingsRepo = SettingsSnapshotRepository(db: db)
        let sessionRepo = SessionRepository(db: db)
        let sequenceRepo = SequenceRepository(db: db)
        let attemptRepo = AttemptRepository(db: db)
        let statsRepo = StatsRepository(db: db)
        let scoring = ScoringService()

        let settings = PracticeSettingsSnapshot(
            key: Key(root: .c),
            scaleType: .major,
            excludedDegrees: [],
            allowedOctaves: [4],
            melodyLength: 2,
            bpm: 80
        )

        let snapshotId = try settingsRepo.insert(snapshot: settings)
        let sessionId = try sessionRepo.startSession(settingsSnapshotId: snapshotId)

        let notes = [
            MelodyNote(midiNoteNumber: 60, startBeat: 0, durationBeats: 2, index: 0), // C4
            MelodyNote(midiNoteNumber: 64, startBeat: 2, durationBeats: 2, index: 1), // E4
        ]

        let sequence = MelodySequence(
            notes: notes,
            key: settings.key,
            scaleType: settings.scaleType,
            excludedDegrees: settings.excludedDegrees,
            allowedOctaves: settings.allowedOctaves,
            bpm: settings.bpm,
            seed: 99
        )

        let ids = try sequenceRepo.insert(sequence: sequence, sessionId: sessionId, settingsSnapshotId: snapshotId)

        let scale = Scale(key: settings.key, type: settings.scaleType)

        let attempt1 = scoring.descriptor(
            expectedNote: notes[0],
            guessedMidiNote: 60,
            previousCorrectExpected: nil,
            previousCorrectGuessed: nil,
            scale: scale,
            isCorrect: true
        )

        try attemptRepo.insertAttempt(
            metadata: attempt1,
            sessionId: sessionId,
            sequenceId: ids.sequenceId,
            melodyNoteId: ids.noteIds[0],
            key: settings.key,
            scaleType: settings.scaleType
        )

        let attempt2 = scoring.descriptor(
            expectedNote: notes[1],
            guessedMidiNote: 65,
            previousCorrectExpected: notes[0].midiNoteNumber,
            previousCorrectGuessed: notes[0].midiNoteNumber,
            scale: scale,
            isCorrect: false
        )

        try attemptRepo.insertAttempt(
            metadata: attempt2,
            sessionId: sessionId,
            sequenceId: ids.sequenceId,
            melodyNoteId: ids.noteIds[1],
            key: settings.key,
            scaleType: settings.scaleType
        )

        let attempt3 = scoring.descriptor(
            expectedNote: notes[1],
            guessedMidiNote: 64,
            previousCorrectExpected: notes[0].midiNoteNumber,
            previousCorrectGuessed: notes[0].midiNoteNumber,
            scale: scale,
            isCorrect: true
        )

        try attemptRepo.insertAttempt(
            metadata: attempt3,
            sessionId: sessionId,
            sequenceId: ids.sequenceId,
            melodyNoteId: ids.noteIds[1],
            key: settings.key,
            scaleType: settings.scaleType
        )

        let degreeBuckets = try statsRepo.mistakeRateByDegree(filter: .allKeys)
        let degree1 = degreeBuckets.first { $0.label == "Degree 1" }
        XCTAssertEqual(degree1?.rate ?? -1, 0.0)

        let degree3 = degreeBuckets.first { $0.label == "Degree 3" }
        XCTAssertEqual(degree3?.rate ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(degree3?.total, 2)

        let intervalBuckets = try statsRepo.mistakeRateByInterval(filter: .allKeys)
        let startBucket = intervalBuckets.first { $0.label == "Start" }
        XCTAssertEqual(startBucket?.rate ?? -1, 0.0)

        let intervalBucket = intervalBuckets.first { $0.label == "4" }
        XCTAssertEqual(intervalBucket?.rate ?? -1, 0.5, accuracy: 0.0001)

        let noteIndexBuckets = try statsRepo.mistakeRateByNoteIndex(filter: .allKeys)
        let note1Bucket = noteIndexBuckets.first { $0.label == "Note 2" }
        XCTAssertEqual(note1Bucket?.rate ?? -1, 0.5, accuracy: 0.0001)
    }

    func testResetHistoryClearsData() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let db = try Database(path: tempURL.path)

        let settingsRepo = SettingsSnapshotRepository(db: db)
        let sessionRepo = SessionRepository(db: db)
        let sequenceRepo = SequenceRepository(db: db)
        let attemptRepo = AttemptRepository(db: db)
        let statsRepo = StatsRepository(db: db)
        let historyRepo = HistoryRepository(db: db)
        let scoring = ScoringService()
        let mistakeQueueRepo = MistakeQueueRepository(db: db)

        let settings = PracticeSettingsSnapshot(
            key: Key(root: .c),
            scaleType: .major,
            excludedDegrees: [],
            allowedOctaves: [4],
            melodyLength: 2,
            bpm: 80
        )

        let snapshotId = try settingsRepo.insert(snapshot: settings)
        let sessionId = try sessionRepo.startSession(settingsSnapshotId: snapshotId)

        let notes = [
            MelodyNote(midiNoteNumber: 60, startBeat: 0, durationBeats: 2, index: 0),
            MelodyNote(midiNoteNumber: 64, startBeat: 2, durationBeats: 2, index: 1)
        ]

        let sequence = MelodySequence(
            notes: notes,
            key: settings.key,
            scaleType: settings.scaleType,
            excludedDegrees: settings.excludedDegrees,
            allowedOctaves: settings.allowedOctaves,
            bpm: settings.bpm,
            seed: 123
        )

        let ids = try sequenceRepo.insert(sequence: sequence, sessionId: sessionId, settingsSnapshotId: snapshotId)
        let scale = Scale(key: settings.key, type: settings.scaleType)

        let attempt1 = scoring.descriptor(
            expectedNote: notes[0],
            guessedMidiNote: 60,
            previousCorrectExpected: nil,
            previousCorrectGuessed: nil,
            scale: scale,
            isCorrect: true
        )

        try attemptRepo.insertAttempt(
            metadata: attempt1,
            sessionId: sessionId,
            sequenceId: ids.sequenceId,
            melodyNoteId: ids.noteIds[0],
            key: settings.key,
            scaleType: settings.scaleType
        )

        let attempt2 = scoring.descriptor(
            expectedNote: notes[1],
            guessedMidiNote: 65,
            previousCorrectExpected: notes[0].midiNoteNumber,
            previousCorrectGuessed: notes[0].midiNoteNumber,
            scale: scale,
            isCorrect: false
        )

        try attemptRepo.insertAttempt(
            metadata: attempt2,
            sessionId: sessionId,
            sequenceId: ids.sequenceId,
            melodyNoteId: ids.noteIds[1],
            key: settings.key,
            scaleType: settings.scaleType
        )

        _ = try mistakeQueueRepo.insert(seed: 1, settings: settings)

        XCTAssertEqual(try attemptRepo.countAttempts(), 2)
        XCTAssertFalse((try mistakeQueueRepo.loadAll()).isEmpty)
        XCTAssertFalse((try statsRepo.mistakeRateByDegree(filter: .allKeys)).isEmpty)

        try historyRepo.resetHistory()

        XCTAssertEqual(try attemptRepo.countAttempts(), 0)
        XCTAssertTrue((try mistakeQueueRepo.loadAll()).isEmpty)
        XCTAssertTrue((try statsRepo.mistakeRateByDegree(filter: .allKeys)).isEmpty)
    }
}
