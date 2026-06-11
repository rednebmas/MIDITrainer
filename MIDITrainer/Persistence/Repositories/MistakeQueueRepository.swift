import Foundation
import SQLite3

/// Repository for persisting and querying the mistake queue.
final class MistakeQueueRepository {
    private let db: Database
    
    init(db: Database) {
        self.db = db
    }
    
    /// Inserts a new mistake into the queue and returns its ID.
    func insert(seed: UInt64, settings: PracticeSettingsSnapshot, sourceName: String? = nil, clearance: Int = 3, now: Date = Date()) throws -> QueuedMistake {
        try db.readWrite { handle in
            let sql = """
            INSERT INTO mistake_queue (seed, settingsJson, sourceName, clearanceDistance, currentClearanceDistance, totalFailures, questionsSinceQueued, queuedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare mistake_queue insert")
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, Int64(bitPattern: seed))

            let encoder = JSONEncoder()
            let settingsData = try encoder.encode(settings)
            let settingsJson = String(data: settingsData, encoding: .utf8) ?? "{}"
            sqlite3_bind_text(statement, 2, settingsJson, -1, SQLITE_TRANSIENT)
            if let sourceName {
                sqlite3_bind_text(statement, 3, sourceName, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_int(statement, 4, Int32(clearance))
            sqlite3_bind_int(statement, 5, Int32(clearance))
            sqlite3_bind_int(statement, 6, 1)
            sqlite3_bind_int(statement, 7, 0)
            sqlite3_bind_double(statement, 8, now.timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to insert mistake_queue")
            }

            let id = sqlite3_last_insert_rowid(handle)
            return QueuedMistake(
                id: id,
                seed: seed,
                settings: settings,
                sourceName: sourceName,
                minimumClearanceDistance: clearance,
                currentClearanceDistance: clearance,
                totalFailures: 1,
                questionsSinceQueued: 0,
                queuedAt: now
            )
        }
    }
    
    /// Loads all active (not yet cleared) mistakes ordered by queuedAt (FIFO).
    func loadAll() throws -> [QueuedMistake] {
        try db.readWrite { handle in
            let sql = """
            SELECT id, seed, settingsJson, sourceName, clearanceDistance, currentClearanceDistance, totalFailures, questionsSinceQueued, queuedAt
            FROM mistake_queue
            WHERE clearedAt IS NULL
            ORDER BY queuedAt ASC;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare mistake_queue select")
            }
            defer { sqlite3_finalize(statement) }

            var mistakes: [QueuedMistake] = []
            let decoder = JSONDecoder()

            while sqlite3_step(statement) == SQLITE_ROW {
                let id = sqlite3_column_int64(statement, 0)
                let seedBits = sqlite3_column_int64(statement, 1)
                let seed = UInt64(bitPattern: seedBits)

                guard let jsonPtr = sqlite3_column_text(statement, 2) else { continue }
                let jsonString = String(cString: jsonPtr)
                guard let jsonData = jsonString.data(using: .utf8),
                      let settings = try? decoder.decode(PracticeSettingsSnapshot.self, from: jsonData) else { continue }

                let sourceName: String?
                if let sourceNamePtr = sqlite3_column_text(statement, 3) {
                    sourceName = String(cString: sourceNamePtr)
                } else {
                    sourceName = nil
                }

                let clearanceDistance = Int(sqlite3_column_int(statement, 4))
                let currentClearanceDistance = Int(sqlite3_column_int(statement, 5))
                let totalFailures: Int? = sqlite3_column_type(statement, 6) == SQLITE_NULL
                    ? nil
                    : Int(sqlite3_column_int(statement, 6))
                let questionsSinceQueued = Int(sqlite3_column_int(statement, 7))
                let queuedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))

                let mistake = QueuedMistake(
                    id: id,
                    seed: seed,
                    settings: settings,
                    sourceName: sourceName,
                    minimumClearanceDistance: clearanceDistance,
                    currentClearanceDistance: currentClearanceDistance,
                    totalFailures: totalFailures,
                    questionsSinceQueued: questionsSinceQueued,
                    queuedAt: queuedAt
                )
                mistakes.append(mistake)
            }

            return mistakes
        }
    }
    
    /// Updates a mistake's distances and counter after a re-ask.
    func update(
        id: Int64,
        minimumClearanceDistance: Int,
        currentClearanceDistance: Int,
        totalFailures: Int?,
        questionsSinceQueued: Int
    ) throws {
        try db.readWrite { handle in
            let sql = """
            UPDATE mistake_queue
            SET clearanceDistance = ?, currentClearanceDistance = ?, totalFailures = ?, questionsSinceQueued = ?
            WHERE id = ?;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare mistake_queue update")
            }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_int(statement, 1, Int32(minimumClearanceDistance))
            sqlite3_bind_int(statement, 2, Int32(currentClearanceDistance))
            if let totalFailures {
                sqlite3_bind_int(statement, 3, Int32(totalFailures))
            } else {
                sqlite3_bind_null(statement, 3)
            }
            sqlite3_bind_int(statement, 4, Int32(questionsSinceQueued))
            sqlite3_bind_int64(statement, 5, id)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to update mistake_queue")
            }
        }
    }
    
    /// Increments questionsSinceQueued for entries, optionally excluding a specific ID.
    func incrementAllCounters(excluding excludedId: Int64? = nil) throws {
        try db.readWrite { handle in
            if let excludedId {
                let sql = "UPDATE mistake_queue SET questionsSinceQueued = questionsSinceQueued + 1 WHERE id != ?;"
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw DatabaseError.statementFailed(message: "Failed to prepare mistake_queue increment with exclusion")
                }
                defer { sqlite3_finalize(statement) }
                
                sqlite3_bind_int64(statement, 1, excludedId)
                
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw DatabaseError.statementFailed(message: "Failed to increment mistake_queue with exclusion")
                }
            } else {
                let sql = "UPDATE mistake_queue SET questionsSinceQueued = questionsSinceQueued + 1;"
                try Database.execute(statement: sql, db: handle)
            }
        }
    }
    
    /// Marks a mistake as cleared by mastery (soft delete). The row stays for
    /// lifetime stats like the melodies-cleared count.
    func markCleared(id: Int64, now: Date = Date()) throws {
        try db.readWrite { handle in
            let sql = "UPDATE mistake_queue SET clearedAt = ? WHERE id = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare mistake_queue markCleared")
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, now.timeIntervalSince1970)
            sqlite3_bind_int64(statement, 2, id)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to mark mistake_queue row cleared")
            }
        }
    }

    /// Removes all active entries from the queue. Cleared rows are kept —
    /// abandoning the queue is not mastery and must not erase that history.
    func deleteAll() throws {
        try db.readWrite { handle in
            try Database.execute(statement: "DELETE FROM mistake_queue WHERE clearedAt IS NULL;", db: handle)
        }
    }
}
