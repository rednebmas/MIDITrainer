import Foundation
import SQLite3

/// Snapshot of the melody queue's strength: how well the queued melodies are
/// known (average clearance gap) and how many have been mastered out.
struct QueueStrength: Equatable {
    let activeCount: Int
    let averageClearance: Double?
    let clearedCount: Int
}

extension StatsRepository {
    func queueStrength() throws -> QueueStrength {
        try db.readWrite { handle in
            let sql = """
            SELECT SUM(CASE WHEN clearedAt IS NULL THEN 1 ELSE 0 END),
                   AVG(CASE WHEN clearedAt IS NULL THEN currentClearanceDistance END),
                   SUM(CASE WHEN clearedAt IS NOT NULL THEN 1 ELSE 0 END)
            FROM mistake_queue;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare queue strength query")
            }
            defer { sqlite3_finalize(statement) }

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw DatabaseError.statementFailed(message: "Failed to read queue strength row")
            }

            let averageClearance: Double? = sqlite3_column_type(statement, 1) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(statement, 1)
            return QueueStrength(
                activeCount: Int(sqlite3_column_int(statement, 0)),
                averageClearance: averageClearance,
                clearedCount: Int(sqlite3_column_int(statement, 2))
            )
        }
    }
}
