import Foundation
import SQLite3

final class AttemptRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func insertAttempt(
        metadata: AttemptMetadata,
        sessionId: Int64,
        sequenceId: Int64,
        melodyNoteId: Int64?,
        key: Key,
        scaleType: ScaleType
    ) throws {
        try db.readWrite { handle in
            let sql = """
            INSERT INTO note_attempt (
                sessionId,
                sequenceId,
                melodyNoteId,
                noteIndexInMelody,
                expectedMidiNoteNumber,
                guessedMidiNoteNumber,
                expectedScaleDegree,
                guessedScaleDegree,
                expectedInterval,
                guessedInterval,
                isCorrect,
                timestamp,
                keyRoot,
                scaleType
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare note_attempt insert")
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, sessionId)
            sqlite3_bind_int64(statement, 2, sequenceId)
            if let melodyNoteId {
                sqlite3_bind_int64(statement, 3, melodyNoteId)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_int(statement, 4, Int32(metadata.noteIndexInMelody))
            sqlite3_bind_int(statement, 5, Int32(metadata.expectedMidiNoteNumber))
            sqlite3_bind_int(statement, 6, Int32(metadata.guessedMidiNoteNumber))

            if let expectedDegree = metadata.expectedScaleDegree {
                sqlite3_bind_int(statement, 7, Int32(expectedDegree.rawValue))
            } else {
                sqlite3_bind_null(statement, 7)
            }

            if let guessedDegree = metadata.guessedScaleDegree {
                sqlite3_bind_int(statement, 8, Int32(guessedDegree.rawValue))
            } else {
                sqlite3_bind_null(statement, 8)
            }

            if let expectedInterval = metadata.expectedInterval {
                sqlite3_bind_int(statement, 9, Int32(expectedInterval.semitones))
            } else {
                sqlite3_bind_null(statement, 9)
            }

            if let guessedInterval = metadata.guessedInterval {
                sqlite3_bind_int(statement, 10, Int32(guessedInterval.semitones))
            } else {
                sqlite3_bind_null(statement, 10)
            }

            sqlite3_bind_int(statement, 11, metadata.isCorrect ? 1 : 0)
            sqlite3_bind_double(statement, 12, metadata.timestamp.timeIntervalSince1970)
            sqlite3_bind_int(statement, 13, Int32(key.root.rawValue))
            sqlite3_bind_text(statement, 14, scaleType.storageKey, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to insert note_attempt")
            }
        }
    }

    func countAttempts() throws -> Int {
        try db.readWrite { handle in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM note_attempt;", -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare count query")
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw DatabaseError.statementFailed(message: "Failed to step count query")
            }
            return Int(sqlite3_column_int(statement, 0))
        }
    }
}
