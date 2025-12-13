import Foundation
import SQLite3

enum StatsFilter {
    case allKeys
    case key(Key, ScaleType)
}

final class StatsRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    func mistakeRateByDegree(filter: StatsFilter) throws -> [StatBucket] {
        try aggregate(
            selectLabel: "expectedScaleDegree",
            labelMapper: { labelValue in
                guard let raw = Int(labelValue) else { return "?" }
                return "Degree \(raw)"
            },
            filter: filter,
            whereClause: "expectedScaleDegree IS NOT NULL"
        )
    }

    func mistakeRateByInterval(filter: StatsFilter) throws -> [StatBucket] {
        try aggregate(
            selectLabel: "COALESCE(expectedInterval, -9999)",
            labelMapper: { value in
                guard let raw = Int(value) else { return "?" }
                return raw == -9999 ? "Start" : "\(raw)"
            },
            filter: filter,
            whereClause: "1=1"
        )
    }

    func mistakeRateByNoteIndex(filter: StatsFilter) throws -> [StatBucket] {
        try aggregate(
            selectLabel: "noteIndexInMelody",
            labelMapper: { value in
                if let intValue = Int(value) {
                    return "Note \(intValue + 1)"
                }
                return "Note \(value)"
            },
            filter: filter,
            whereClause: "1=1"
        )
    }

    func degreeConfusionCounts(filter: StatsFilter) throws -> [ConfusionBucket] {
        try confusionCounts(
            expectedColumn: "expectedScaleDegree",
            guessedColumn: "guessedScaleDegree",
            expectedLabel: { value in
                guard let raw = Int(value) else { return "?" }
                return "Degree \(raw)"
            },
            guessedLabel: { value in
                guard let raw = Int(value) else { return "?" }
                return "Degree \(raw)"
            },
            filter: filter,
            whereClause: "expectedScaleDegree IS NOT NULL AND guessedScaleDegree IS NOT NULL"
        )
    }

    func intervalConfusionCounts(filter: StatsFilter) throws -> [ConfusionBucket] {
        try confusionCounts(
            expectedColumn: "expectedInterval",
            guessedColumn: "guessedInterval",
            expectedLabel: { value in
                guard let raw = Int(value) else { return "?" }
                return raw == -9999 ? "Start" : "\(raw)"
            },
            guessedLabel: { value in
                guard let raw = Int(value) else { return "?" }
                return raw == -9999 ? "Start" : "\(raw)"
            },
            filter: filter,
            whereClause: "1=1"
        )
    }

    private func aggregate(
        selectLabel: String,
        labelMapper: (String) -> String,
        filter: StatsFilter,
        whereClause: String
    ) throws -> [StatBucket] {
        try db.readWrite { handle in
            var query = """
            SELECT \(selectLabel) as label,
                SUM(CASE WHEN isCorrect = 0 THEN 1 ELSE 0 END) as mistakes,
                COUNT(*) as attempts
            FROM note_attempt
            WHERE \(whereClause)
            """
            let filterValues = filterBindings(filter: filter)
            query += filterValues.clause
            query += " GROUP BY label ORDER BY label;"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare stats aggregate query")
            }
            defer { sqlite3_finalize(statement) }

            bind(filterValues.bindings, to: statement)

            var buckets: [StatBucket] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let labelValue = String(cString: sqlite3_column_text(statement, 0))
                let mistakes = sqlite3_column_int(statement, 1)
                let attempts = sqlite3_column_int(statement, 2)
                let rate = attempts > 0 ? Double(mistakes) / Double(attempts) : 0
                buckets.append(
                    StatBucket(
                        label: labelMapper(labelValue),
                        rate: rate,
                        total: Int(attempts)
                    )
                )
            }
            return buckets
        }
    }

    private func confusionCounts(
        expectedColumn: String,
        guessedColumn: String,
        expectedLabel: (String) -> String,
        guessedLabel: (String) -> String,
        filter: StatsFilter,
        whereClause: String
    ) throws -> [ConfusionBucket] {
        try db.readWrite { handle in
            var query = """
            SELECT COALESCE(\(expectedColumn), -9999) as expected,
                   COALESCE(\(guessedColumn), -9999) as guessed,
                   COUNT(*) as count
            FROM note_attempt
            WHERE \(whereClause)
            """
            let filterValues = filterBindings(filter: filter)
            query += filterValues.clause
            query += " GROUP BY expected, guessed;"

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare confusion query")
            }
            defer { sqlite3_finalize(statement) }

            bind(filterValues.bindings, to: statement)

            var buckets: [ConfusionBucket] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let expectedValue = String(cString: sqlite3_column_text(statement, 0))
                let guessedValue = String(cString: sqlite3_column_text(statement, 1))
                let count = sqlite3_column_int(statement, 2)
                buckets.append(
                    ConfusionBucket(
                        expectedLabel: expectedLabel(expectedValue),
                        guessedLabel: guessedLabel(guessedValue),
                        count: Int(count)
                    )
                )
            }
            return buckets
        }
    }

    private func filterBindings(filter: StatsFilter) -> (clause: String, bindings: [Binding]) {
        switch filter {
        case .allKeys:
            return ("", [])
        case .key(let key, let scaleType):
            return (" AND keyRoot = ? AND scaleType = ?", [.int(Int32(key.root.rawValue)), .text(scaleType.storageKey)])
        }
    }

    private enum Binding {
        case int(Int32)
        case text(String)
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer?) {
        for (index, binding) in bindings.enumerated() {
            let idx = Int32(index + 1)
            switch binding {
            case .int(let value):
                sqlite3_bind_int(statement, idx, value)
            case .text(let value):
                sqlite3_bind_text(statement, idx, value, -1, SQLITE_TRANSIENT)
            }
        }
    }
}
