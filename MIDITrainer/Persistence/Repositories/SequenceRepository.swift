import Foundation
import SQLite3

struct PersistedSequenceIDs {
    let sequenceId: Int64
    let noteIds: [Int64]
}

final class SequenceRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func insert(sequence: MelodySequence, sessionId: Int64, settingsSnapshotId: Int64) throws -> PersistedSequenceIDs {
        try db.readWrite { handle in
            let sequenceId = try insertSequence(sequence: sequence, sessionId: sessionId, settingsSnapshotId: settingsSnapshotId, db: handle)
            let noteIds = try insertNotes(sequenceId: sequenceId, notes: sequence.notes, db: handle)
            return PersistedSequenceIDs(sequenceId: sequenceId, noteIds: noteIds)
        }
    }

    private func insertSequence(sequence: MelodySequence, sessionId: Int64, settingsSnapshotId: Int64, db: OpaquePointer) throws -> Int64 {
        let sql = """
        INSERT INTO melody_sequence (sessionId, settingsSnapshotId, seed, createdAt)
        VALUES (?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.statementFailed(message: "Failed to prepare melody_sequence insert")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, sessionId)
        sqlite3_bind_int64(statement, 2, settingsSnapshotId)
        if let seed = sequence.seed {
            sqlite3_bind_int64(statement, 3, Int64(bitPattern: seed))
        } else {
            sqlite3_bind_null(statement, 3)
        }
        sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.statementFailed(message: "Failed to insert melody_sequence")
        }

        return sqlite3_last_insert_rowid(db)
    }

    private func insertNotes(sequenceId: Int64, notes: [MelodyNote], db: OpaquePointer) throws -> [Int64] {
        let sql = """
        INSERT INTO melody_note (sequenceId, noteIndex, startBeat, durationBeats, midiNoteNumber)
        VALUES (?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.statementFailed(message: "Failed to prepare melody_note insert")
        }
        defer { sqlite3_finalize(statement) }

        var ids: [Int64] = []
        ids.reserveCapacity(notes.count)

        for note in notes {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            sqlite3_bind_int64(statement, 1, sequenceId)
            sqlite3_bind_int(statement, 2, Int32(note.index))
            sqlite3_bind_double(statement, 3, note.startBeat)
            sqlite3_bind_double(statement, 4, note.durationBeats)
            sqlite3_bind_int(statement, 5, Int32(note.midiNoteNumber))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to insert melody_note")
            }

            ids.append(sqlite3_last_insert_rowid(db))
        }

        return ids
    }
}
