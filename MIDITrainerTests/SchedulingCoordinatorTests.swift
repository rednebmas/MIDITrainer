import XCTest
@testable import MIDITrainer

final class SchedulingCoordinatorTests: XCTestCase {
    private var db: Database!
    private var mistakeRepo: MistakeQueueRepository!
    private var fragmentRepo: FragmentQueueRepository!
    private var statsRepo: StatsRepository!
    private let settings = PracticeSettingsSnapshot()

    override func setUp() {
        super.setUp()
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).sqlite"
        db = try! Database(path: path)
        mistakeRepo = MistakeQueueRepository(db: db)
        fragmentRepo = FragmentQueueRepository(db: db)
        statsRepo = StatsRepository(db: db)
    }

    private func makeCoordinator(
        clearance: Int = 3,
        minPasses: Int = 3,
        initialMode: SchedulerMode = .spacedMistakes
    ) -> SchedulingCoordinator {
        SchedulingCoordinator(
            initialMode: initialMode,
            repository: mistakeRepo,
            fragmentRepository: fragmentRepo,
            statsRepository: statsRepo,
            spacedMistakeClearance: { clearance },
            spacedMistakeMinPasses: { minPasses },
            onModeChange: { _ in }
        )
    }

    private func seedAndActivateReask(_ coordinator: SchedulingCoordinator, clearance: Int = 3) -> Int64 {
        coordinator.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        for seed in UInt64(200)..<UInt64(200 + clearance) {
            _ = coordinator.nextQuestion(currentSettings: settings)
            coordinator.recordCompletion(seed: seed, settings: settings, hadErrors: false, mistakeId: nil, sourceName: nil)
        }
        let reask = coordinator.nextQuestion(currentSettings: settings)
        guard case .reask(_, _, let id) = reask else {
            XCTFail("Expected reask to become due, got \(reask)")
            return -1
        }
        return id
    }

    // MARK: - Core RED test

    func testActiveMistakeIdPersistsThroughCorrectReaskUntilNextQuestion() {
        let coordinator = makeCoordinator()
        let mistakeId = seedAndActivateReask(coordinator)
        XCTAssertEqual(coordinator.activeMistakeId, mistakeId, "activeMistakeId should be set when reask is served")

        coordinator.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: mistakeId, sourceName: nil)

        XCTAssertEqual(coordinator.activeMistakeId, mistakeId,
                       "activeMistakeId must persist through correct re-ask completion — the UI still displays that mistake until the next question starts")

        _ = coordinator.nextQuestion(currentSettings: settings)
        XCTAssertNotEqual(coordinator.activeMistakeId, mistakeId,
                          "activeMistakeId should update at the next-question boundary (either nil for fresh or a new reask id)")
    }

    // MARK: - Regression guards

    func testActiveMistakeIdStaysAfterFailedReask() {
        let coordinator = makeCoordinator()
        let mistakeId = seedAndActivateReask(coordinator)

        coordinator.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: mistakeId, sourceName: nil)

        XCTAssertEqual(coordinator.activeMistakeId, mistakeId,
                       "Failed re-ask should not clear activeMistakeId — a replay will test the same mistake")
    }

    func testActiveMistakeIdClearsOnDefer() {
        let coordinator = makeCoordinator()
        _ = seedAndActivateReask(coordinator)

        coordinator.deferCurrentMistake()

        XCTAssertNil(coordinator.activeMistakeId, "deferCurrentMistake should clear activeMistakeId")
    }

    func testActiveMistakeIdClearsOnClearQueue() {
        let coordinator = makeCoordinator()
        _ = seedAndActivateReask(coordinator)

        coordinator.clearQueue()

        XCTAssertNil(coordinator.activeMistakeId, "clearQueue should clear activeMistakeId")
    }
}
