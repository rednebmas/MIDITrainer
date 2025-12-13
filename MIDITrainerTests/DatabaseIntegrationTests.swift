import XCTest
@testable import MIDITrainer

final class DatabaseIntegrationTests: XCTestCase {
    func testMigrationsAndBasicInsert() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let db = try Database(path: tempURL.path)

        let settingsRepo = SettingsSnapshotRepository(db: db)
        let sessionRepo = SessionRepository(db: db)
        let sequenceRepo = SequenceRepository(db: db)
        let attemptRepo = AttemptRepository(db: db)
        let scoring = ScoringService()

        let settings = PracticeSettingsSnapshot(
            key: Key(root: .d),
            scaleType: .dorian,
            excludedDegrees: [.iv],
            allowedOctaves: [4],
            melodyLength: 2,
            bpm: 90
        )

        let snapshotId = try settingsRepo.insert(snapshot: settings)
        let sessionId = try sessionRepo.startSession(settingsSnapshotId: snapshotId)

        let notes = [
            MelodyNote(midiNoteNumber: 62, startBeat: 0, durationBeats: 2, index: 0),
            MelodyNote(midiNoteNumber: 65, startBeat: 2, durationBeats: 2, index: 1),
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
        XCTAssertEqual(ids.noteIds.count, sequence.notes.count)

        let descriptor = scoring.descriptor(
            expectedNote: notes[0],
            guessedMidiNote: 62,
            previousCorrectExpected: nil,
            previousCorrectGuessed: nil,
            scale: Scale(key: settings.key, type: settings.scaleType),
            isCorrect: true
        )

        try attemptRepo.insertAttempt(
            metadata: descriptor,
            sessionId: sessionId,
            sequenceId: ids.sequenceId,
            melodyNoteId: ids.noteIds.first,
            key: settings.key,
            scaleType: settings.scaleType
        )

        XCTAssertEqual(try attemptRepo.countAttempts(), 1)
    }
}
