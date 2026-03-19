import Foundation
import SQLite3

extension StatsRepository {
    func recoveryStats(filter: StatsFilter) throws -> RecoveryStats? {
        try db.readWrite { handle in
            var sql = """
            WITH pass_counts AS (
                SELECT sequenceId, COUNT(*) as num_passes
                FROM note_attempt
                WHERE noteIndexInMelody = 0
            """
            let filterValues = filterBindings(filter: filter)
            sql += filterValues.clause
            sql += """

                GROUP BY sequenceId
                HAVING num_passes > 1
            )
            SELECT AVG(CAST(num_passes AS REAL)), COUNT(*)
            FROM pass_counts;
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare recovery stats query")
            }
            defer { sqlite3_finalize(statement) }
            bind(filterValues.bindings, to: statement)

            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            let count = Int(sqlite3_column_int(statement, 1))
            guard count > 0 else { return nil }

            return RecoveryStats(
                averageAttempts: sqlite3_column_double(statement, 0),
                totalRecoveries: count
            )
        }
    }

    func recoveryTrend(filter: StatsFilter, windowSize: Int = 50) throws -> [TrendPoint] {
        let raw = try recoveryPassCounts(filter: filter)
        guard raw.count >= windowSize else { return [] }
        return rollingAverage(over: raw, windowSize: windowSize)
    }

    private func recoveryPassCounts(filter: StatsFilter) throws -> [Int] {
        try db.readWrite { handle in
            var sql = """
            WITH pass_counts AS (
                SELECT na.sequenceId, COUNT(*) as num_passes, ms.createdAt
                FROM note_attempt na
                JOIN melody_sequence ms ON ms.id = na.sequenceId
                WHERE na.noteIndexInMelody = 0
            """
            let filterValues = filterBindings(filter: filter)
            sql += filterValues.clause
            sql += """

                GROUP BY na.sequenceId
                HAVING num_passes > 1
            )
            SELECT num_passes FROM pass_counts ORDER BY createdAt;
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare recovery trend query")
            }
            defer { sqlite3_finalize(statement) }
            bind(filterValues.bindings, to: statement)

            var rows: [Int] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(Int(sqlite3_column_int(statement, 0)))
            }
            return rows
        }
    }

    private func rollingAverage(over data: [Int], windowSize: Int) -> [TrendPoint] {
        var points: [TrendPoint] = []
        var windowSum = 0
        for (i, passes) in data.enumerated() {
            windowSum += passes
            if i >= windowSize { windowSum -= data[i - windowSize] }
            guard i >= windowSize - 1 else { continue }
            let avg = Double(windowSum) / Double(windowSize)
            points.append(TrendPoint(id: i, value: avg))
        }
        return points
    }

    func recoveryDistribution(filter: StatsFilter) throws -> [StatBucket] {
        try db.readWrite { handle in
            var sql = """
            WITH pass_counts AS (
                SELECT sequenceId, COUNT(*) as num_passes
                FROM note_attempt
                WHERE noteIndexInMelody = 0
            """
            let filterValues = filterBindings(filter: filter)
            sql += filterValues.clause
            sql += """

                GROUP BY sequenceId
                HAVING num_passes > 1
            )
            SELECT
                CASE WHEN num_passes >= 5 THEN '5+' ELSE CAST(num_passes AS TEXT) END as label,
                COUNT(*) as count
            FROM pass_counts
            GROUP BY label
            ORDER BY MIN(num_passes);
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare recovery distribution query")
            }
            defer { sqlite3_finalize(statement) }
            bind(filterValues.bindings, to: statement)

            var buckets: [StatBucket] = []
            var totalCount = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                let label = String(cString: sqlite3_column_text(statement, 0))
                let count = Int(sqlite3_column_int(statement, 1))
                totalCount += count
                buckets.append(StatBucket(label: label, rate: 0, total: count))
            }

            guard totalCount > 0 else { return buckets }
            return buckets.map {
                StatBucket(label: $0.label, rate: Double($0.total) / Double(totalCount), total: $0.total)
            }
        }
    }
}
