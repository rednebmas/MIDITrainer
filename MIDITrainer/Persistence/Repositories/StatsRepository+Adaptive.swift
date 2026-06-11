import Foundation
import SQLite3

struct IntervalAccuracy: Equatable {
    let semitones: Int
    let successCount: Int
    let total: Int
}

struct FirstGuessIntervalStats: Equatable {
    let intervals: [IntervalAccuracy]
    let start: IntervalAccuracy?

    var totalAttempts: Int {
        intervals.reduce(start?.total ?? 0) { $0 + $1.total }
    }
}

/// Queries restricted to the first guess at each note (MIN attempt id per
/// melody_note row). All-attempt rates overcount errors on hard intervals
/// because the user keeps guessing until correct.
extension StatsRepository {
    private static let firstGuessOnly = """
    id IN (SELECT MIN(id) FROM note_attempt WHERE melodyNoteId IS NOT NULL GROUP BY melodyNoteId)
    """

    func firstGuessAccuracyByInterval(filter: StatsFilter, since: Date? = nil) throws -> FirstGuessIntervalStats {
        try db.readWrite { handle in
            var query = """
            SELECT COALESCE(expectedInterval, -9999) as semitones,
                   SUM(isCorrect) as successes,
                   COUNT(*) as attempts
            FROM note_attempt
            WHERE \(Self.firstGuessOnly)
            """
            let filterValues = filterBindings(filter: filter)
            query += filterValues.clause
            if since != nil {
                query += " AND timestamp >= ?"
            }
            query += " GROUP BY semitones;"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare first-guess interval query")
            }
            defer { sqlite3_finalize(statement) }

            bind(filterValues.bindings, to: statement)
            if let since {
                sqlite3_bind_double(statement, Int32(filterValues.bindings.count + 1), since.timeIntervalSince1970)
            }

            var intervals: [IntervalAccuracy] = []
            var start: IntervalAccuracy?
            while sqlite3_step(statement) == SQLITE_ROW {
                let semitones = Int(sqlite3_column_int(statement, 0))
                let entry = IntervalAccuracy(
                    semitones: semitones,
                    successCount: Int(sqlite3_column_int(statement, 1)),
                    total: Int(sqlite3_column_int(statement, 2))
                )
                if semitones == -9999 {
                    start = entry
                } else {
                    intervals.append(entry)
                }
            }
            return FirstGuessIntervalStats(intervals: intervals, start: start)
        }
    }

    /// The most recent first-guess note results, oldest first.
    func recentFirstGuessResults(filter: StatsFilter, limit: Int) throws -> [Bool] {
        try db.readWrite { handle in
            var query = """
            SELECT isCorrect FROM note_attempt
            WHERE \(Self.firstGuessOnly)
            """
            let filterValues = filterBindings(filter: filter)
            query += filterValues.clause
            query += " ORDER BY timestamp DESC LIMIT ?;"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare recent first-guess query")
            }
            defer { sqlite3_finalize(statement) }

            bind(filterValues.bindings, to: statement)
            sqlite3_bind_int(statement, Int32(filterValues.bindings.count + 1), Int32(max(limit, 0)))

            var results: [Bool] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(sqlite3_column_int(statement, 0) == 1)
            }
            return results.reversed()
        }
    }
}
