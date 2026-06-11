import XCTest
@testable import MIDITrainer

final class MistakeQueueClearedTests: XCTestCase {
    private var db: Database!
    private var repo: MistakeQueueRepository!
    private var stats: StatsRepository!
    private let settings = PracticeSettingsSnapshot()

    override func setUp() {
        super.setUp()
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).sqlite"
        db = try! Database(path: path)
        repo = MistakeQueueRepository(db: db)
        stats = StatsRepository(db: db)
    }

    func testMarkClearedHidesRowFromLoadAll() throws {
        let mistake = try repo.insert(seed: 100, settings: settings)
        _ = try repo.insert(seed: 101, settings: settings)
        try repo.markCleared(id: mistake.id)

        let active = try repo.loadAll()
        XCTAssertEqual(active.map(\.seed), [101])
    }

    func testDeleteAllPreservesClearedHistory() throws {
        let cleared = try repo.insert(seed: 100, settings: settings)
        _ = try repo.insert(seed: 101, settings: settings)
        try repo.markCleared(id: cleared.id)

        try repo.deleteAll()

        XCTAssertEqual(try repo.loadAll().count, 0)
        XCTAssertEqual(try stats.queueStrength().clearedCount, 1, "abandoning the queue must not erase mastery history")
    }

    func testQueueStrengthAveragesActiveClearances() throws {
        let first = try repo.insert(seed: 100, settings: settings, clearance: 3)
        try repo.update(id: first.id, currentClearance: 9, totalFailures: 1, questionsWaited: 0)
        _ = try repo.insert(seed: 101, settings: settings, clearance: 3)
        let cleared = try repo.insert(seed: 102, settings: settings, clearance: 3)
        try repo.markCleared(id: cleared.id)

        let strength = try stats.queueStrength()
        XCTAssertEqual(strength.activeCount, 2)
        XCTAssertEqual(strength.clearedCount, 1)
        XCTAssertEqual(strength.averageClearance ?? 0, 6.0, accuracy: 1e-9, "(9 + 3) / 2")
    }

    func testQueueStrengthOnEmptyTable() throws {
        let strength = try stats.queueStrength()
        XCTAssertEqual(strength, QueueStrength(activeCount: 0, averageClearance: nil, clearedCount: 0))
    }

    func testMigratesFromV8Database() throws {
        let v8Path = NSTemporaryDirectory() + "test_v8_\(UUID().uuidString).sqlite"
        let v8Migrations = Database.defaultMigrations.filter { $0.version <= 8 }
        _ = try Database(path: v8Path, migrations: v8Migrations)

        let migrated = try Database(path: v8Path)
        let migratedRepo = MistakeQueueRepository(db: migrated)
        let mistake = try migratedRepo.insert(seed: 100, settings: settings)
        try migratedRepo.markCleared(id: mistake.id)
        XCTAssertEqual(try StatsRepository(db: migrated).queueStrength().clearedCount, 1)
    }

    func testV10MigrationRenamesColumnsAndBackfillsFailures() throws {
        let v9Path = NSTemporaryDirectory() + "test_v9_\(UUID().uuidString).sqlite"
        let v9Migrations = Database.defaultMigrations.filter { $0.version <= 9 }
        let v9db = try Database(path: v9Path, migrations: v9Migrations)

        let settingsJson = String(data: try JSONEncoder().encode(settings), encoding: .utf8)!
        try v9db.readWrite { handle in
            try Database.execute(statement: """
            INSERT INTO mistake_queue (seed, settingsJson, clearanceDistance, currentClearanceDistance, totalFailures, questionsSinceQueued, queuedAt)
            VALUES (999, '\(settingsJson)', 30, 50, NULL, 2, 1700000000);
            """, db: handle)
        }

        let migrated = try Database(path: v9Path)
        let loaded = try MistakeQueueRepository(db: migrated).loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].totalFailures, 10, "NULL failures backfilled from legacy minimum: 30 / 3")
        XCTAssertEqual(loaded[0].currentClearance, 50, "raw value carried over; schedulers clamp on load")
        XCTAssertEqual(loaded[0].questionsWaited, 2)
    }
}
