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

    func testFirstTryAccuracyForCurrentSettings() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let db = try Database(path: tempURL.path)

        let settingsRepo = SettingsSnapshotRepository(db: db)
        let sessionRepo = SessionRepository(db: db)
        let sequenceRepo = SequenceRepository(db: db)
        let attemptRepo = AttemptRepository(db: db)
        let statsRepo = StatsRepository(db: db)
        let scoring = ScoringService()

        let settingsA = PracticeSettingsSnapshot(
            key: Key(root: .c),
            scaleType: .major,
            excludedDegrees: [],
            allowedOctaves: [4],
            melodyLength: 2,
            bpm: 80
        )

        let settingsB = PracticeSettingsSnapshot(
            key: Key(root: .d),
            scaleType: .major,
            excludedDegrees: [],
            allowedOctaves: [4],
            melodyLength: 2,
            bpm: 80
        )

        let snapshotA = try settingsRepo.insert(snapshot: settingsA)
        let sessionA = try sessionRepo.startSession(settingsSnapshotId: snapshotA)

        let snapshotB = try settingsRepo.insert(snapshot: settingsB)
        let sessionB = try sessionRepo.startSession(settingsSnapshotId: snapshotB)

        let notes = [
            MelodyNote(midiNoteNumber: 60, startBeat: 0, durationBeats: 2, index: 0),
            MelodyNote(midiNoteNumber: 64, startBeat: 2, durationBeats: 2, index: 1)
        ]

        let sequence1 = MelodySequence(
            notes: notes,
            key: settingsA.key,
            scaleType: settingsA.scaleType,
            excludedDegrees: settingsA.excludedDegrees,
            allowedOctaves: settingsA.allowedOctaves,
            bpm: settingsA.bpm,
            seed: 1
        )
        let ids1 = try sequenceRepo.insert(sequence: sequence1, sessionId: sessionA, settingsSnapshotId: snapshotA)

        let scaleA = Scale(key: settingsA.key, type: settingsA.scaleType)

        let seq1Attempt1 = scoring.descriptor(
            expectedNote: notes[0],
            guessedMidiNote: 60,
            previousCorrectExpected: nil,
            previousCorrectGuessed: nil,
            scale: scaleA,
            isCorrect: true
        )

        try attemptRepo.insertAttempt(
            metadata: seq1Attempt1,
            sessionId: sessionA,
            sequenceId: ids1.sequenceId,
            melodyNoteId: ids1.noteIds[0],
            key: settingsA.key,
            scaleType: settingsA.scaleType
        )

        let seq1Attempt2 = scoring.descriptor(
            expectedNote: notes[1],
            guessedMidiNote: 64,
            previousCorrectExpected: notes[0].midiNoteNumber,
            previousCorrectGuessed: notes[0].midiNoteNumber,
            scale: scaleA,
            isCorrect: true
        )

        try attemptRepo.insertAttempt(
            metadata: seq1Attempt2,
            sessionId: sessionA,
            sequenceId: ids1.sequenceId,
            melodyNoteId: ids1.noteIds[1],
            key: settingsA.key,
            scaleType: settingsA.scaleType
        )

        let sequence2 = MelodySequence(
            notes: notes,
            key: settingsA.key,
            scaleType: settingsA.scaleType,
            excludedDegrees: settingsA.excludedDegrees,
            allowedOctaves: settingsA.allowedOctaves,
            bpm: settingsA.bpm,
            seed: 2
        )
        let ids2 = try sequenceRepo.insert(sequence: sequence2, sessionId: sessionA, settingsSnapshotId: snapshotA)

        let seq2Attempt1 = scoring.descriptor(
            expectedNote: notes[0],
            guessedMidiNote: 60,
            previousCorrectExpected: nil,
            previousCorrectGuessed: nil,
            scale: scaleA,
            isCorrect: true
        )

        try attemptRepo.insertAttempt(
            metadata: seq2Attempt1,
            sessionId: sessionA,
            sequenceId: ids2.sequenceId,
            melodyNoteId: ids2.noteIds[0],
            key: settingsA.key,
            scaleType: settingsA.scaleType
        )

        let seq2Attempt2 = scoring.descriptor(
            expectedNote: notes[1],
            guessedMidiNote: 65, // wrong
            previousCorrectExpected: notes[0].midiNoteNumber,
            previousCorrectGuessed: notes[0].midiNoteNumber,
            scale: scaleA,
            isCorrect: false
        )

        try attemptRepo.insertAttempt(
            metadata: seq2Attempt2,
            sessionId: sessionA,
            sequenceId: ids2.sequenceId,
            melodyNoteId: ids2.noteIds[1],
            key: settingsA.key,
            scaleType: settingsA.scaleType
        )

        // Sequence with different settings should not count
        let sequenceOther = MelodySequence(
            notes: notes,
            key: settingsB.key,
            scaleType: settingsB.scaleType,
            excludedDegrees: settingsB.excludedDegrees,
            allowedOctaves: settingsB.allowedOctaves,
            bpm: settingsB.bpm,
            seed: 3
        )

        let idsOther = try sequenceRepo.insert(sequence: sequenceOther, sessionId: sessionB, settingsSnapshotId: snapshotB)
        let scaleB = Scale(key: settingsB.key, type: settingsB.scaleType)
        let otherAttempt = scoring.descriptor(
            expectedNote: notes[0],
            guessedMidiNote: 62,
            previousCorrectExpected: nil,
            previousCorrectGuessed: nil,
            scale: scaleB,
            isCorrect: false
        )
        try attemptRepo.insertAttempt(
            metadata: otherAttempt,
            sessionId: sessionB,
            sequenceId: idsOther.sequenceId,
            melodyNoteId: idsOther.noteIds[0],
            key: settingsB.key,
            scaleType: settingsB.scaleType
        )

        let accuracy = try statsRepo.firstTryAccuracy(for: settingsA, limit: 20)
        XCTAssertEqual(accuracy?.totalCount, 2)
        XCTAssertEqual(accuracy?.successCount, 1)
        XCTAssertEqual(accuracy?.rate ?? -1, 0.5, accuracy: 0.0001)
    }

    func testFirstTryAccuracyUsesLast20Sequences() throws {
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
            melodyLength: 1,
            bpm: 80
        )

        let snapshot = try settingsRepo.insert(snapshot: settings)
        let session = try sessionRepo.startSession(settingsSnapshotId: snapshot)
        let note = MelodyNote(midiNoteNumber: 60, startBeat: 0, durationBeats: 4, index: 0)
        let scale = Scale(key: settings.key, type: settings.scaleType)
        let baseTime = Date().timeIntervalSince1970 - 1000

        for i in 0..<21 {
            let sequence = MelodySequence(
                notes: [note],
                key: settings.key,
                scaleType: settings.scaleType,
                excludedDegrees: settings.excludedDegrees,
                allowedOctaves: settings.allowedOctaves,
                bpm: settings.bpm,
                seed: UInt64(i)
            )
            let ids = try sequenceRepo.insert(sequence: sequence, sessionId: session, settingsSnapshotId: snapshot)

            // Explicitly set createdAt so ordering is deterministic
            try db.readWrite { handle in
                let adjusted = baseTime + Double(i)
                try Database.execute(statement: "UPDATE melody_sequence SET createdAt = \(adjusted) WHERE id = \(ids.sequenceId);", db: handle)
            }

            let attempt = scoring.descriptor(
                expectedNote: note,
                guessedMidiNote: 60,
                previousCorrectExpected: nil,
                previousCorrectGuessed: nil,
                scale: scale,
                isCorrect: i == 0 // only the oldest sequence is fully correct
            )

            try attemptRepo.insertAttempt(
                metadata: attempt,
                sessionId: session,
                sequenceId: ids.sequenceId,
                melodyNoteId: ids.noteIds[0],
                key: settings.key,
                scaleType: settings.scaleType
            )
        }

        let accuracy = try statsRepo.firstTryAccuracy(for: settings, limit: 20)
        XCTAssertEqual(accuracy?.totalCount, 20)
        // The only success should be the oldest sequence, which is outside the last 20
        XCTAssertEqual(accuracy?.successCount, 0)
        XCTAssertEqual(accuracy?.rate ?? -1, 0.0, accuracy: 0.0001)
    }
}
