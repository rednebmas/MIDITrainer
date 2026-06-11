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
        try repo.update(id: first.id, minimumClearanceDistance: 9, currentClearanceDistance: 9, totalFailures: 1, questionsSinceQueued: 0)
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
}
