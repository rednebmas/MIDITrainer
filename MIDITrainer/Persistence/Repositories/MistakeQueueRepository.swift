import Foundation
import SQLite3

/// Repository for persisting and querying the mistake queue.
final class MistakeQueueRepository {
    private let db: Database
    
    init(db: Database) {
        self.db = db
    }
    
    /// Inserts a new mistake into the queue and returns its ID.
    func insert(seed: UInt64, settings: PracticeSettingsSnapshot) throws -> Int64 {
        try db.readWrite { handle in
            let sql = """
            INSERT INTO mistake_queue (seed, settingsJson, clearanceDistance, questionsSinceQueued, queuedAt)
            VALUES (?, ?, ?, ?, ?);
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
            sqlite3_bind_int(statement, 3, 1) // Initial clearance distance
            sqlite3_bind_int(statement, 4, 0) // Initial questions since queued
            sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to insert mistake_queue")
            }
            
            return sqlite3_last_insert_rowid(handle)
        }
    }
    
    /// Loads all queued mistakes ordered by queuedAt (FIFO).
    func loadAll() throws -> [QueuedMistake] {
        try db.readWrite { handle in
            let sql = """
            SELECT id, seed, settingsJson, clearanceDistance, questionsSinceQueued, queuedAt
            FROM mistake_queue
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
                
                let clearanceDistance = Int(sqlite3_column_int(statement, 3))
                let questionsSinceQueued = Int(sqlite3_column_int(statement, 4))
                let queuedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                
                let mistake = QueuedMistake(
                    id: id,
                    seed: seed,
                    settings: settings,
                    clearanceDistance: clearanceDistance,
                    questionsSinceQueued: questionsSinceQueued,
                    queuedAt: queuedAt
                )
                mistakes.append(mistake)
            }
            
            return mistakes
        }
    }
    
    /// Updates a mistake's clearance distance and counter after a re-ask.
    func update(id: Int64, clearanceDistance: Int, questionsSinceQueued: Int) throws {
        try db.readWrite { handle in
            let sql = """
            UPDATE mistake_queue
            SET clearanceDistance = ?, questionsSinceQueued = ?
            WHERE id = ?;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare mistake_queue update")
            }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_int(statement, 1, Int32(clearanceDistance))
            sqlite3_bind_int(statement, 2, Int32(questionsSinceQueued))
            sqlite3_bind_int64(statement, 3, id)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to update mistake_queue")
            }
        }
    }
    
    /// Increments questionsSinceQueued for all entries (called after each fresh question).
    func incrementAllCounters() throws {
        try db.readWrite { handle in
            let sql = "UPDATE mistake_queue SET questionsSinceQueued = questionsSinceQueued + 1;"
            try Database.execute(statement: sql, db: handle)
        }
    }
    
    /// Removes a mistake from the queue (when answered correctly on a due re-ask).
    func delete(id: Int64) throws {
        try db.readWrite { handle in
            let sql = "DELETE FROM mistake_queue WHERE id = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare mistake_queue delete")
            }
            defer { sqlite3_finalize(statement) }
            
            sqlite3_bind_int64(statement, 1, id)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to delete from mistake_queue")
            }
        }
    }
    
    /// Clears all entries from the queue.
    func deleteAll() throws {
        try db.readWrite { handle in
            try Database.execute(statement: "DELETE FROM mistake_queue;", db: handle)
        }
    }
}
