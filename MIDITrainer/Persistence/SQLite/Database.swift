import Foundation
import SQLite3

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct Migration {
    let version: Int
    let statements: [String]
}

final class Database {
    private let db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.sambender.miditrainer.sqlite")
    private let migrations: [Migration]

    init(path: String = Database.defaultPath(), migrations: [Migration] = Database.defaultMigrations) throws {
        var handle: OpaquePointer?
        if sqlite3_open(path, &handle) != SQLITE_OK {
            throw DatabaseError.openFailed(message: String(cString: sqlite3_errmsg(handle)))
        }
        db = handle
        self.migrations = migrations
        try migrateIfNeeded()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func readWrite<T>(_ block: (OpaquePointer) throws -> T) rethrows -> T {
        try queue.sync {
            guard let db else { throw DatabaseError.invalidHandle }
            return try block(db)
        }
    }

    private func migrateIfNeeded() throws {
        try readWrite { db in
            let currentVersion = try Database.userVersion(db: db)
            let sortedMigrations = migrations.sorted { $0.version < $1.version }
            for migration in sortedMigrations where migration.version > currentVersion {
                for statement in migration.statements {
                    try Database.execute(statement: statement, db: db)
                }
                try Database.execute(statement: "PRAGMA user_version = \(migration.version);", db: db)
            }
        }
    }
}

extension Database {
    static func defaultPath() -> String {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let baseURL = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return baseURL.appendingPathComponent("miditrainer.sqlite").path
    }

    static let defaultMigrations: [Migration] = {
        let initialClearance = QueuedMistake.initialClearanceDistance
        return [
            Migration(version: 1, statements: [
                """
                CREATE TABLE IF NOT EXISTS settings_snapshot (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    keyRoot INTEGER NOT NULL,
                    scaleType TEXT NOT NULL,
                    excludedDegrees TEXT NOT NULL,
                    allowedOctaves TEXT NOT NULL,
                    melodyLength INTEGER NOT NULL,
                    bpm INTEGER NOT NULL,
                    createdAt REAL NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS practice_session (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    settingsSnapshotId INTEGER NOT NULL,
                    startedAt REAL NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS melody_sequence (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    sessionId INTEGER NOT NULL,
                    settingsSnapshotId INTEGER NOT NULL,
                    seed INTEGER,
                    createdAt REAL NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS melody_note (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    sequenceId INTEGER NOT NULL,
                    noteIndex INTEGER NOT NULL,
                    startBeat REAL NOT NULL,
                    durationBeats REAL NOT NULL,
                    midiNoteNumber INTEGER NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS note_attempt (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    sessionId INTEGER NOT NULL,
                    sequenceId INTEGER NOT NULL,
                    melodyNoteId INTEGER,
                    noteIndexInMelody INTEGER NOT NULL,
                    expectedMidiNoteNumber INTEGER NOT NULL,
                    guessedMidiNoteNumber INTEGER NOT NULL,
                    expectedScaleDegree INTEGER,
                    guessedScaleDegree INTEGER,
                    expectedInterval INTEGER,
                    guessedInterval INTEGER,
                    isCorrect INTEGER NOT NULL,
                    timestamp REAL NOT NULL,
                    keyRoot INTEGER NOT NULL,
                    scaleType TEXT NOT NULL
                );
                """,
                "CREATE INDEX IF NOT EXISTS idx_note_attempt_key ON note_attempt(keyRoot, scaleType);",
                "CREATE INDEX IF NOT EXISTS idx_note_attempt_expectedScaleDegree ON note_attempt(expectedScaleDegree);",
                "CREATE INDEX IF NOT EXISTS idx_note_attempt_guessedScaleDegree ON note_attempt(guessedScaleDegree);",
                "CREATE INDEX IF NOT EXISTS idx_note_attempt_expectedInterval ON note_attempt(expectedInterval);",
                "CREATE INDEX IF NOT EXISTS idx_note_attempt_guessedInterval ON note_attempt(guessedInterval);",
                "CREATE INDEX IF NOT EXISTS idx_note_attempt_noteIndexInMelody ON note_attempt(noteIndexInMelody);",
                "CREATE INDEX IF NOT EXISTS idx_note_attempt_sequenceId ON note_attempt(sequenceId);",
                "CREATE INDEX IF NOT EXISTS idx_note_attempt_sessionId ON note_attempt(sessionId);",
                "CREATE INDEX IF NOT EXISTS idx_note_attempt_timestamp ON note_attempt(timestamp);"
            ]),
            Migration(version: 2, statements: [
                """
                CREATE TABLE IF NOT EXISTS mistake_queue (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    seed INTEGER NOT NULL,
                    settingsJson TEXT NOT NULL,
                    clearanceDistance INTEGER NOT NULL DEFAULT \(initialClearance),
                    questionsSinceQueued INTEGER NOT NULL DEFAULT 0,
                    queuedAt REAL NOT NULL
                );
                """,
                "CREATE INDEX IF NOT EXISTS idx_mistake_queue_queuedAt ON mistake_queue(queuedAt);"
            ]),
            Migration(version: 3, statements: [
                "ALTER TABLE mistake_queue ADD COLUMN currentClearanceDistance INTEGER NOT NULL DEFAULT \(initialClearance);"
            ])
        ]
    }()
}

enum DatabaseError: Error {
    case openFailed(message: String)
    case invalidHandle
    case statementFailed(message: String)
}

extension Database {
    static func execute(statement: String, db: OpaquePointer) throws {
        var errMsg: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, statement, nil, nil, &errMsg)
        if result != SQLITE_OK {
            let message = errMsg.flatMap { String(cString: $0) } ?? "Unknown"
            sqlite3_free(errMsg)
            throw DatabaseError.statementFailed(message: message)
        }
    }

    static func userVersion(db: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) != SQLITE_OK {
            throw DatabaseError.statementFailed(message: "Failed to prepare user_version pragma")
        }
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            let version = sqlite3_column_int(statement, 0)
            return Int(version)
        } else {
            throw DatabaseError.statementFailed(message: "Failed to read user_version pragma")
        }
    }
}

extension Database {
    func lastInsertedRowID(db: OpaquePointer) -> Int64 {
        sqlite3_last_insert_rowid(db)
    }
}
