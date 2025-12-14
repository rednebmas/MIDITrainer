import Foundation
import SQLite3

enum StatsFilter {
    case allKeys
    case key(Key, ScaleType)
}

struct FirstTryAccuracy {
    let successCount: Int
    let totalCount: Int

    var rate: Double {
        guard totalCount > 0 else { return 0 }
        return Double(successCount) / Double(totalCount)
    }
}

struct SequenceHistoryEntry: Identifiable {
    let id: Int64
    let midiNotes: [UInt8]
    let wasCorrectFirstTry: Bool
    let createdAt: Date
}

struct WeaknessEntry: Equatable {
    let seed: UInt64
    let timesAsked: Int
    let firstAttemptFailures: Int

    var weight: Double {
        Double(firstAttemptFailures)
    }
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

    /// Computes the first-try accuracy for the last N sequences (default 20) that match the exact current settings.
    /// A sequence counts as a success if it has zero incorrect attempts recorded.
    func firstTryAccuracy(for settings: PracticeSettingsSnapshot, limit: Int = 20) throws -> FirstTryAccuracy? {
        try db.readWrite { handle in
            let excluded = try encode(degrees: settings.excludedDegrees)
            let allowed = try encode(octaves: settings.allowedOctaves)
            let sql = """
            WITH filtered AS (
                SELECT ms.id
                FROM melody_sequence ms
                JOIN settings_snapshot ss ON ms.settingsSnapshotId = ss.id
                WHERE ss.keyRoot = ?
                  AND ss.scaleType = ?
                  AND ss.excludedDegrees = ?
                  AND ss.allowedOctaves = ?
                  AND ss.melodyLength = ?
                  AND ss.bpm = ?
                ORDER BY ms.createdAt DESC
                LIMIT ?
            ),
            mistakes AS (
                SELECT sequenceId, SUM(CASE WHEN isCorrect = 0 THEN 1 ELSE 0 END) as mistakeCount
                FROM note_attempt
                GROUP BY sequenceId
            )
            SELECT COUNT(*) as total,
                   SUM(CASE WHEN COALESCE(mistakes.mistakeCount, 0) = 0 THEN 1 ELSE 0 END) as successCount
            FROM filtered
            LEFT JOIN mistakes ON mistakes.sequenceId = filtered.id;
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare first-try accuracy query")
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int(statement, 1, Int32(settings.key.root.rawValue))
            sqlite3_bind_text(statement, 2, settings.scaleType.storageKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, excluded, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, allowed, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 5, Int32(settings.melodyLength))
            sqlite3_bind_int(statement, 6, Int32(settings.bpm))
            sqlite3_bind_int(statement, 7, Int32(max(limit, 0)))

            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw DatabaseError.statementFailed(message: "Failed to read first-try accuracy row")
            }

            let total = Int(sqlite3_column_int(statement, 0))
            let successes = Int(sqlite3_column_int(statement, 1))

            guard total > 0 else { return nil }

            return FirstTryAccuracy(successCount: successes, totalCount: total)
        }
    }

    /// Fetches the last N sequences with their notes and first-try status for the given settings.
    func sequenceHistory(for settings: PracticeSettingsSnapshot, limit: Int = 20) throws -> [SequenceHistoryEntry] {
        try db.readWrite { handle in
            let excluded = try encode(degrees: settings.excludedDegrees)
            let allowed = try encode(octaves: settings.allowedOctaves)

            // First, get the sequence IDs, their creation dates, and whether they had mistakes
            let sequencesSql = """
            WITH filtered AS (
                SELECT ms.id, ms.createdAt
                FROM melody_sequence ms
                JOIN settings_snapshot ss ON ms.settingsSnapshotId = ss.id
                WHERE ss.keyRoot = ?
                  AND ss.scaleType = ?
                  AND ss.excludedDegrees = ?
                  AND ss.allowedOctaves = ?
                  AND ss.melodyLength = ?
                  AND ss.bpm = ?
                ORDER BY ms.createdAt DESC
                LIMIT ?
            ),
            mistakes AS (
                SELECT sequenceId, SUM(CASE WHEN isCorrect = 0 THEN 1 ELSE 0 END) as mistakeCount
                FROM note_attempt
                GROUP BY sequenceId
            )
            SELECT filtered.id, filtered.createdAt, COALESCE(mistakes.mistakeCount, 0) as mistakeCount
            FROM filtered
            LEFT JOIN mistakes ON mistakes.sequenceId = filtered.id
            ORDER BY filtered.createdAt DESC;
            """

            var sequencesStmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sequencesSql, -1, &sequencesStmt, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare sequence history query")
            }
            defer { sqlite3_finalize(sequencesStmt) }

            sqlite3_bind_int(sequencesStmt, 1, Int32(settings.key.root.rawValue))
            sqlite3_bind_text(sequencesStmt, 2, settings.scaleType.storageKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(sequencesStmt, 3, excluded, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(sequencesStmt, 4, allowed, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(sequencesStmt, 5, Int32(settings.melodyLength))
            sqlite3_bind_int(sequencesStmt, 6, Int32(settings.bpm))
            sqlite3_bind_int(sequencesStmt, 7, Int32(max(limit, 0)))

            var sequenceData: [(id: Int64, createdAt: Double, wasCorrect: Bool)] = []
            while sqlite3_step(sequencesStmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(sequencesStmt, 0)
                let createdAt = sqlite3_column_double(sequencesStmt, 1)
                let mistakeCount = sqlite3_column_int(sequencesStmt, 2)
                sequenceData.append((id: id, createdAt: createdAt, wasCorrect: mistakeCount == 0))
            }

            // Now fetch notes for each sequence
            var entries: [SequenceHistoryEntry] = []
            entries.reserveCapacity(sequenceData.count)

            let notesSql = "SELECT midiNoteNumber FROM melody_note WHERE sequenceId = ? ORDER BY noteIndex;"
            var notesStmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, notesSql, -1, &notesStmt, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare notes query")
            }
            defer { sqlite3_finalize(notesStmt) }

            for seq in sequenceData {
                sqlite3_reset(notesStmt)
                sqlite3_clear_bindings(notesStmt)
                sqlite3_bind_int64(notesStmt, 1, seq.id)

                var midiNotes: [UInt8] = []
                while sqlite3_step(notesStmt) == SQLITE_ROW {
                    let midiNote = UInt8(sqlite3_column_int(notesStmt, 0))
                    midiNotes.append(midiNote)
                }

                entries.append(SequenceHistoryEntry(
                    id: seq.id,
                    midiNotes: midiNotes,
                    wasCorrectFirstTry: seq.wasCorrect,
                    createdAt: Date(timeIntervalSince1970: seq.createdAt)
                ))
            }

            return entries
        }
    }

    /// Returns sequences (by seed) with the most first-attempt failures for the given settings.
    /// A first-attempt failure is when any note in a sequence had isCorrect=0 on its first try.
    /// - Parameter matchExactSettings: If true, matches all settings. If false, only key and scale type.
    func topWeaknesses(for settings: PracticeSettingsSnapshot, limit: Int = 20, matchExactSettings: Bool = false) throws -> [WeaknessEntry] {
        try db.readWrite { handle in
            // For each sequence (melody_sequence row), determine if ANY note had isCorrect=0
            // Then aggregate by seed to count first-attempt failures across multiple askings
            let sql: String
            if matchExactSettings {
                let excluded = try encode(degrees: settings.excludedDegrees)
                let allowed = try encode(octaves: settings.allowedOctaves)
                sql = """
                WITH sequence_had_mistake AS (
                    SELECT
                        ms.id as sequenceId,
                        ms.seed,
                        MAX(CASE WHEN na.isCorrect = 0 THEN 1 ELSE 0 END) as hadMistake
                    FROM melody_sequence ms
                    JOIN settings_snapshot ss ON ms.settingsSnapshotId = ss.id
                    LEFT JOIN note_attempt na ON na.sequenceId = ms.id
                    WHERE ss.keyRoot = \(settings.key.root.rawValue)
                      AND ss.scaleType = '\(settings.scaleType.storageKey)'
                      AND ss.excludedDegrees = '\(excluded)'
                      AND ss.allowedOctaves = '\(allowed)'
                      AND ss.melodyLength = \(settings.melodyLength)
                      AND ss.bpm = \(settings.bpm)
                    GROUP BY ms.id, ms.seed
                )
                SELECT
                    seed,
                    COUNT(*) as timesAsked,
                    SUM(hadMistake) as firstAttemptFailures
                FROM sequence_had_mistake
                GROUP BY seed
                HAVING firstAttemptFailures > 0
                ORDER BY firstAttemptFailures DESC
                LIMIT \(max(limit, 0));
                """
            } else {
                sql = """
                WITH sequence_had_mistake AS (
                    SELECT
                        ms.id as sequenceId,
                        ms.seed,
                        MAX(CASE WHEN na.isCorrect = 0 THEN 1 ELSE 0 END) as hadMistake
                    FROM melody_sequence ms
                    JOIN settings_snapshot ss ON ms.settingsSnapshotId = ss.id
                    LEFT JOIN note_attempt na ON na.sequenceId = ms.id
                    WHERE ss.keyRoot = ?
                      AND ss.scaleType = ?
                    GROUP BY ms.id, ms.seed
                )
                SELECT
                    seed,
                    COUNT(*) as timesAsked,
                    SUM(hadMistake) as firstAttemptFailures
                FROM sequence_had_mistake
                GROUP BY seed
                HAVING firstAttemptFailures > 0
                ORDER BY firstAttemptFailures DESC
                LIMIT ?;
                """
            }

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                throw DatabaseError.statementFailed(message: "Failed to prepare top weaknesses query")
            }
            defer { sqlite3_finalize(statement) }

            if !matchExactSettings {
                sqlite3_bind_int(statement, 1, Int32(settings.key.root.rawValue))
                sqlite3_bind_text(statement, 2, settings.scaleType.storageKey, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(statement, 3, Int32(max(limit, 0)))
            }

            var entries: [WeaknessEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let seed = UInt64(bitPattern: sqlite3_column_int64(statement, 0))
                let timesAsked = Int(sqlite3_column_int(statement, 1))
                let failures = Int(sqlite3_column_int(statement, 2))

                entries.append(WeaknessEntry(
                    seed: seed,
                    timesAsked: timesAsked,
                    firstAttemptFailures: failures
                ))
            }

            return entries
        }
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

    private func encode(degrees: Set<ScaleDegree>) throws -> String {
        let raw = Array(degrees).map { $0.rawValue }.sorted()
        let data = try JSONEncoder().encode(raw)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func encode(octaves: [Int]) throws -> String {
        let data = try JSONEncoder().encode(octaves)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
