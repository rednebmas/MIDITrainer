import Foundation
import SQLite3

/// Repository for persisting 2-note fragment drills queued by adaptive mode.
final class FragmentQueueRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func insert(
        _ fragment: ExtractedFragment,
        parentMistakeId: Int64?,
        sourceName: String?,
        now: Date = Date()
    ) throws -> QueuedFragment {
        try db.readWrite { handle in
            let sql = """
            INSERT INTO fragment_queue (parentMistakeId, fromDegree, fromOctave, toDegree, toOctave,
                intervalSemitones, sourceName, consecutiveCorrect, questionsSinceAsked, totalFailures, queuedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, 1, ?);
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare fragment_queue insert")
            }
            defer { sqlite3_finalize(statement) }

            if let parentMistakeId {
                sqlite3_bind_int64(statement, 1, parentMistakeId)
            } else {
                sqlite3_bind_null(statement, 1)
            }
            sqlite3_bind_int(statement, 2, Int32(fragment.fromDegree.rawValue))
            sqlite3_bind_int(statement, 3, Int32(fragment.fromOctave))
            sqlite3_bind_int(statement, 4, Int32(fragment.toDegree.rawValue))
            sqlite3_bind_int(statement, 5, Int32(fragment.toOctave))
            sqlite3_bind_int(statement, 6, Int32(fragment.intervalSemitones))
            if let sourceName {
                sqlite3_bind_text(statement, 7, sourceName, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(statement, 7)
            }
            sqlite3_bind_double(statement, 8, now.timeIntervalSince1970)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to insert fragment_queue")
            }

            return QueuedFragment(
                id: sqlite3_last_insert_rowid(handle),
                parentMistakeId: parentMistakeId,
                fromDegree: fragment.fromDegree,
                fromOctave: fragment.fromOctave,
                toDegree: fragment.toDegree,
                toOctave: fragment.toOctave,
                intervalSemitones: fragment.intervalSemitones,
                sourceName: sourceName,
                consecutiveCorrect: 0,
                questionsSinceAsked: 0,
                totalFailures: 1,
                queuedAt: now
            )
        }
    }

    func loadAll() throws -> [QueuedFragment] {
        try db.readWrite { handle in
            let sql = """
            SELECT id, parentMistakeId, fromDegree, fromOctave, toDegree, toOctave,
                   intervalSemitones, sourceName, consecutiveCorrect, questionsSinceAsked, totalFailures, queuedAt
            FROM fragment_queue
            ORDER BY queuedAt ASC, id ASC;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare fragment_queue select")
            }
            defer { sqlite3_finalize(statement) }

            var fragments: [QueuedFragment] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let fromDegree = ScaleDegree(rawValue: Int(sqlite3_column_int(statement, 2))),
                      let toDegree = ScaleDegree(rawValue: Int(sqlite3_column_int(statement, 4))) else { continue }
                let parentMistakeId: Int64? = sqlite3_column_type(statement, 1) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_int64(statement, 1)
                let sourceName: String? = sqlite3_column_text(statement, 7).map { String(cString: $0) }
                fragments.append(QueuedFragment(
                    id: sqlite3_column_int64(statement, 0),
                    parentMistakeId: parentMistakeId,
                    fromDegree: fromDegree,
                    fromOctave: Int(sqlite3_column_int(statement, 3)),
                    toDegree: toDegree,
                    toOctave: Int(sqlite3_column_int(statement, 5)),
                    intervalSemitones: Int(sqlite3_column_int(statement, 6)),
                    sourceName: sourceName,
                    consecutiveCorrect: Int(sqlite3_column_int(statement, 8)),
                    questionsSinceAsked: Int(sqlite3_column_int(statement, 9)),
                    totalFailures: Int(sqlite3_column_int(statement, 10)),
                    queuedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11))
                ))
            }
            return fragments
        }
    }

    func update(id: Int64, consecutiveCorrect: Int, questionsSinceAsked: Int, totalFailures: Int) throws {
        try db.readWrite { handle in
            let sql = """
            UPDATE fragment_queue
            SET consecutiveCorrect = ?, questionsSinceAsked = ?, totalFailures = ?
            WHERE id = ?;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare fragment_queue update")
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(consecutiveCorrect))
            sqlite3_bind_int(statement, 2, Int32(questionsSinceAsked))
            sqlite3_bind_int(statement, 3, Int32(totalFailures))
            sqlite3_bind_int64(statement, 4, id)

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to update fragment_queue")
            }
        }
    }

    func incrementAllCounters(excluding excludedId: Int64? = nil) throws {
        try db.readWrite { handle in
            if let excludedId {
                let sql = "UPDATE fragment_queue SET questionsSinceAsked = questionsSinceAsked + 1 WHERE id != ?;"
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw DatabaseError.statementFailed(message: "Failed to prepare fragment_queue increment")
                }
                defer { sqlite3_finalize(statement) }
                sqlite3_bind_int64(statement, 1, excludedId)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw DatabaseError.statementFailed(message: "Failed to increment fragment_queue")
                }
            } else {
                try Database.execute(statement: "UPDATE fragment_queue SET questionsSinceAsked = questionsSinceAsked + 1;", db: handle)
            }
        }
    }

    func delete(id: Int64) throws {
        try db.readWrite { handle in
            let sql = "DELETE FROM fragment_queue WHERE id = ?;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare fragment_queue delete")
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, id)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw DatabaseError.statementFailed(message: "Failed to delete from fragment_queue")
            }
        }
    }

    func deleteAll() throws {
        try db.readWrite { handle in
            try Database.execute(statement: "DELETE FROM fragment_queue;", db: handle)
        }
    }
}
