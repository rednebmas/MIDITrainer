import XCTest
@testable import MIDITrainer

final class FragmentQueueRepositoryTests: XCTestCase {
    private var path: String!
    private var db: Database!
    private var repo: FragmentQueueRepository!
    private let fragment = ExtractedFragment(
        fromDegree: .v, fromOctave: 4, toDegree: .i, toOctave: 5, intervalSemitones: 5
    )

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "test_\(UUID().uuidString).sqlite"
        db = try! Database(path: path)
        repo = FragmentQueueRepository(db: db)
    }

    func testInsertAndLoadRoundTrip() throws {
        // Whole-second timestamp: fractional epoch seconds can lose a ULP in
        // the 1970↔2001 reference conversion and break Date equality.
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let inserted = try repo.insert(fragment, parentMistakeId: 7, sourceName: "Dark Horse", now: now)
        let loaded = try repo.loadAll()
        XCTAssertEqual(loaded, [inserted])
        XCTAssertEqual(loaded[0].parentMistakeId, 7)
        XCTAssertEqual(loaded[0].consecutiveCorrect, 0)
        XCTAssertEqual(loaded[0].totalFailures, 1)
    }

    func testNilParentAndSourceRoundTrip() throws {
        _ = try repo.insert(fragment, parentMistakeId: nil, sourceName: nil)
        let loaded = try repo.loadAll()
        XCTAssertNil(loaded[0].parentMistakeId)
        XCTAssertNil(loaded[0].sourceName)
    }

    func testUpdatePersistsCounters() throws {
        let inserted = try repo.insert(fragment, parentMistakeId: nil, sourceName: nil)
        try repo.update(id: inserted.id, consecutiveCorrect: 2, questionsSinceAsked: 1, totalFailures: 3)
        let loaded = try repo.loadAll()[0]
        XCTAssertEqual(loaded.consecutiveCorrect, 2)
        XCTAssertEqual(loaded.questionsSinceAsked, 1)
        XCTAssertEqual(loaded.totalFailures, 3)
    }

    func testIncrementAllCountersWithExclusion() throws {
        let first = try repo.insert(fragment, parentMistakeId: nil, sourceName: nil)
        let second = try repo.insert(fragment, parentMistakeId: nil, sourceName: nil)
        try repo.incrementAllCounters(excluding: first.id)
        try repo.incrementAllCounters()
        let byId = Dictionary(uniqueKeysWithValues: try repo.loadAll().map { ($0.id, $0) })
        XCTAssertEqual(byId[first.id]?.questionsSinceAsked, 1)
        XCTAssertEqual(byId[second.id]?.questionsSinceAsked, 2)
    }

    func testDelete() throws {
        let inserted = try repo.insert(fragment, parentMistakeId: nil, sourceName: nil)
        _ = try repo.insert(fragment, parentMistakeId: nil, sourceName: nil)
        try repo.delete(id: inserted.id)
        XCTAssertEqual(try repo.loadAll().count, 1)
        try repo.deleteAll()
        XCTAssertEqual(try repo.loadAll().count, 0)
    }

    func testMigratesFromV7Database() throws {
        let v7Path = NSTemporaryDirectory() + "test_v7_\(UUID().uuidString).sqlite"
        let v7Migrations = Database.defaultMigrations.filter { $0.version <= 7 }
        _ = try Database(path: v7Path, migrations: v7Migrations)

        let migrated = try Database(path: v7Path)
        let migratedRepo = FragmentQueueRepository(db: migrated)
        _ = try migratedRepo.insert(fragment, parentMistakeId: nil, sourceName: nil)
        XCTAssertEqual(try migratedRepo.loadAll().count, 1)
    }
}
