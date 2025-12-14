import Foundation
import SQLite3

final class SettingsSnapshotRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func insert(snapshot: PracticeSettingsSnapshot) throws -> Int64 {
        try db.readWrite { handle in
            let sql = """
            INSERT INTO settings_snapshot (keyRoot, scaleType, excludedDegrees, allowedOctaves, melodyLength, bpm, createdAt)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare settings_snapshot insert")
            }
            defer { sqlite3_finalize(statement) }

            let excluded = try JSONEncoder().encode(snapshot.excludedDegrees.map { $0.rawValue }.sorted())
            let allowed = try JSONEncoder().encode(snapshot.allowedOctaves)
            let now = Date().timeIntervalSince1970

            sqlite3_bind_int(statement, 1, Int32(snapshot.key.root.rawValue))
            sqlite3_bind_text(statement, 2, snapshot.scaleType.storageKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, String(data: excluded, encoding: .utf8) ?? "[]", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, String(data: allowed, encoding: .utf8) ?? "[]", -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 5, Int32(snapshot.melodyLength))
            sqlite3_bind_int(statement, 6, Int32(snapshot.bpm))
            sqlite3_bind_double(statement, 7, now)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to insert settings_snapshot")
            }

            return sqlite3_last_insert_rowid(handle)
        }
    }
}
