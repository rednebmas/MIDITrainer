import Foundation
import SQLite3

final class SessionRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func startSession(settingsSnapshotId: Int64) throws -> Int64 {
        try db.readWrite { handle in
            let sql = """
            INSERT INTO practice_session (settingsSnapshotId, startedAt)
            VALUES (?, ?);
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare practice_session insert")
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, settingsSnapshotId)
            sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to insert practice_session")
            }

            return sqlite3_last_insert_rowid(handle)
        }
    }
}
