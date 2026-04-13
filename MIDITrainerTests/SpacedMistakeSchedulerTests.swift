import XCTest
@testable import MIDITrainer

final class SpacedMistakeSchedulerTests: XCTestCase {
    private var db: Database!
    private var repo: MistakeQueueRepository!
    private let settings = PracticeSettingsSnapshot()

    override func setUp() {
        super.setUp()
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).sqlite"
        db = try! Database(path: path)
        repo = MistakeQueueRepository(db: db)
    }

    // MARK: - Fresh question failure adds to queue

    func testFreshQuestionFailureAddsToQueue() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        let q1 = scheduler.nextQuestion(currentSettings: settings)
        XCTAssertEqual(q1, .fresh)

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)

        XCTAssertEqual(scheduler.pendingCount, 1)
        let snapshot = scheduler.queueSnapshot
        XCTAssertEqual(snapshot[0].seed, 100)
        XCTAssertEqual(snapshot[0].minimumClearanceDistance, 3)
        XCTAssertEqual(snapshot[0].currentClearanceDistance, 3)
        XCTAssertEqual(snapshot[0].questionsSinceQueued, 0)
    }

    // MARK: - Re-ask becomes due after enough fresh questions

    func testReaskBecomesDueAfterClearance() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        for seed in UInt64(200)...201 {
            let q = scheduler.nextQuestion(currentSettings: settings)
            XCTAssertEqual(q, .fresh)
            scheduler.recordCompletion(seed: seed, settings: settings, hadErrors: false, mistakeId: nil, sourceName: nil)
        }
        XCTAssertEqual(scheduler.queueSnapshot[0].questionsSinceQueued, 2)

        let q = scheduler.nextQuestion(currentSettings: settings)
        XCTAssertEqual(q, .fresh)
        scheduler.recordCompletion(seed: 202, settings: settings, hadErrors: false, mistakeId: nil, sourceName: nil)

        let next = scheduler.nextQuestion(currentSettings: settings)
        if case .reask(let seed, _, let id) = next {
            XCTAssertEqual(seed, 100)
            XCTAssertEqual(id, mistakeId)
        } else {
            XCTFail("Expected reask, got fresh")
        }
    }

    // MARK: - Failure resets currentClearanceDistance

    func testReaskFailureResetsCurrentClearance() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        XCTAssertEqual(scheduler.queueSnapshot[0].currentClearanceDistance, 3)

        // Fail first re-ask
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        let reask1 = scheduler.nextQuestion(currentSettings: settings)
        guard case .reask(_, _, let id1) = reask1 else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: id1, sourceName: nil)

        let after1 = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(after1.minimumClearanceDistance, 6, "min should increase: 3 + 3 = 6")
        XCTAssertEqual(after1.currentClearanceDistance, 3, "current should RESET to base clearance")
        XCTAssertEqual(after1.questionsSinceQueued, 0)

        // Fail second re-ask
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        let reask2 = scheduler.nextQuestion(currentSettings: settings)
        guard case .reask(_, _, let id2) = reask2 else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: id2, sourceName: nil)

        let after2 = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(after2.minimumClearanceDistance, 9, "min should increase: 6 + 3 = 9")
        XCTAssertEqual(after2.currentClearanceDistance, 3, "current should RESET to base clearance again")

        // Fail third re-ask
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        let reask3 = scheduler.nextQuestion(currentSettings: settings)
        guard case .reask(_, _, let id3) = reask3 else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: id3, sourceName: nil)

        let after3 = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(after3.minimumClearanceDistance, 12)
        XCTAssertEqual(after3.currentClearanceDistance, 3, "current always resets to base on failure")
    }

    func testCurrentClearanceStaysAtBaseAfterManyFailures() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        // Simulate 10 consecutive re-ask failures
        for _ in 0..<10 {
            advanceFreshQuestions(scheduler: scheduler, count: 3)
            let reask = scheduler.nextQuestion(currentSettings: settings)
            guard case .reask(_, _, let rid) = reask else { return XCTFail("Expected reask") }
            scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid, sourceName: nil)

            let entry = scheduler.queueSnapshot.first { $0.id == mistakeId }!
            XCTAssertEqual(entry.currentClearanceDistance, 3,
                           "current should always be base clearance after failure")
        }

        let final = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(final.minimumClearanceDistance, 33,
                       "min should be 3 + 10*3 = 33")
        XCTAssertEqual(final.currentClearanceDistance, 3,
                       "current should still be base clearance, never grows")
    }

    func testFailureCountTracksNonDefaultClearance() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 5 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id
        XCTAssertEqual(scheduler.queueSnapshot[0].totalFailures, Optional(1))

        advanceFreshQuestions(scheduler: scheduler, count: 5)
        guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else {
            return XCTFail("Expected reask")
        }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid, sourceName: nil)

        let updated = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(updated.minimumClearanceDistance, 10)
        XCTAssertEqual(updated.currentClearanceDistance, 5)
        XCTAssertEqual(updated.totalFailures, Optional(2))
    }

    func testFailureCountDoesNotDependOnSpacingMath() {
        var clearance = 3
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { clearance })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id
        XCTAssertEqual(scheduler.queueSnapshot[0].totalFailures, Optional(1))

        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid1) = scheduler.nextQuestion(currentSettings: settings) else {
            return XCTFail("Expected reask")
        }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid1, sourceName: nil)

        clearance = 5

        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid2) = scheduler.nextQuestion(currentSettings: settings) else {
            return XCTFail("Expected reask")
        }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid2, sourceName: nil)

        advanceFreshQuestions(scheduler: scheduler, count: 5)
        guard case .reask(_, _, let rid3) = scheduler.nextQuestion(currentSettings: settings) else {
            return XCTFail("Expected reask")
        }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid3, sourceName: nil)

        let updated = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(updated.minimumClearanceDistance, 16)
        XCTAssertEqual(updated.currentClearanceDistance, 5)
        XCTAssertEqual(updated.totalFailures, Optional(4), "Failure count should track actual failures, not be derived from spacing values")
    }

    // MARK: - Success increases currentClearanceDistance

    func testSuccessfulReaskClearsWhenCurrentEqualsMin() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        // Pass the re-ask (current == min == 3) → cleared immediately
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        let reask = scheduler.nextQuestion(currentSettings: settings)
        guard case .reask(_, _, let rid) = reask else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid, sourceName: nil)

        XCTAssertEqual(scheduler.pendingCount, 0, "Should be cleared when current == min")
        XCTAssertNil(scheduler.queueSnapshot.first { $0.id == mistakeId })
    }

    func testSuccessfulReaskRequiresTwoPassesAfterFailure() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        // Fail re-ask: min=6, current=3
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid1) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid1, sourceName: nil)

        // Pass 1: current=3, 3 >= 6? NO → bump to 6
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid2) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid2, sourceName: nil)

        XCTAssertEqual(scheduler.pendingCount, 1, "Not cleared yet after first pass")
        let after = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(after.currentClearanceDistance, 6, "current bumped to 6")

        // Pass 2: current=6, 6 >= 6? YES → cleared
        advanceFreshQuestions(scheduler: scheduler, count: 6)
        guard case .reask(_, _, let rid3) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid3, sourceName: nil)

        XCTAssertEqual(scheduler.pendingCount, 0, "Cleared after second pass")
        XCTAssertNil(scheduler.queueSnapshot.first { $0.id == mistakeId })
    }

    func testClearsWhenCurrentReachesMin() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        // Fresh question fails → min=3, current=3
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        // Re-ask fails → min=6, current=3
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid1) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid1, sourceName: nil)

        // Re-ask succeeds → check: 3 >= 6? NO → current bumps to 6. Still in queue.
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid2) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid2, sourceName: nil)
        XCTAssertEqual(scheduler.pendingCount, 1, "Not cleared yet — current was below min")

        // Re-ask succeeds again → check: current(6) >= min(6)? YES → cleared!
        // Bug: with '>', 6 > 6 is false → bumped to 9, creating an unnecessary extra pass.
        advanceFreshQuestions(scheduler: scheduler, count: 6)
        guard case .reask(_, _, let rid3) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid3, sourceName: nil)

        XCTAssertEqual(scheduler.pendingCount, 0,
                       "Mistake should clear when current == min, not require an extra pass")
        XCTAssertNil(scheduler.queueSnapshot.first { $0.id == mistakeId })
    }

    // MARK: - Mixed results: failure resets progress

    func testFailureAfterSuccessResetsCurrentClearance() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        // Fail re-ask twice: min=9, current=3
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid1) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid1, sourceName: nil)
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid2) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid2, sourceName: nil)

        // Pass re-ask: current bumps from 3 to 6 (still < min=9, not cleared)
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid3) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid3, sourceName: nil)

        let afterPass = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(afterPass.currentClearanceDistance, 6, "current bumped on success")
        XCTAssertEqual(afterPass.minimumClearanceDistance, 9, "min unchanged on success")

        // Fail next re-ask: current should reset back to 3, min bumps to 12
        advanceFreshQuestions(scheduler: scheduler, count: 6)
        guard case .reask(_, _, let rid4) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid4, sourceName: nil)

        let afterFail = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(afterFail.currentClearanceDistance, 3, "current resets to base on failure")
        XCTAssertEqual(afterFail.minimumClearanceDistance, 12, "min increases on failure: 9 + 3 = 12")
    }

    // MARK: - Load queue preserves failure reset

    func testLoadQueuePreservesCurrentBelowMin() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        // Fail a fresh question, then fail the re-ask (current resets to 3, min=6)
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid, sourceName: nil)

        let before = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(before.currentClearanceDistance, 3, "current should be base after failure")
        XCTAssertEqual(before.minimumClearanceDistance, 6, "min should be bumped")

        // Simulate app restart by creating a new scheduler from the same DB
        let reloaded = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })
        let after = reloaded.queueSnapshot.first { $0.id == mistakeId }!

        XCTAssertEqual(after.currentClearanceDistance, 3,
                       "loadQueue must NOT boost current back to min — failure reset must survive restart")
        XCTAssertEqual(after.minimumClearanceDistance, 6, "min unchanged on reload")
        XCTAssertEqual(after.totalFailures, Optional(2), "Persisted failure count should survive reload")
    }

    func testLoadQueueCapsLegacyCurrentAboveMin() {
        // Simulate legacy data: current > min (from old code before failure-reset fix)
        let mistake = try! repo.insert(seed: 999, settings: settings, sourceName: nil, clearance: 3)

        // Manually update to simulate legacy state: min=50, current=70
        try! repo.update(
            id: mistake.id,
            minimumClearanceDistance: 50,
            currentClearanceDistance: 70,
            totalFailures: nil,
            questionsSinceQueued: 0
        )

        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })
        let loaded = scheduler.queueSnapshot.first { $0.id == mistake.id }!

        XCTAssertEqual(loaded.currentClearanceDistance, 50,
                       "loadQueue should cap current to min for legacy entries where current > min")
        XCTAssertEqual(loaded.minimumClearanceDistance, 50, "min unchanged")
        XCTAssertNil(loaded.totalFailures, "Legacy rows without a persisted failure count should stay unknown")
    }

    // MARK: - Helpers

    private func advanceFreshQuestions(scheduler: SpacedMistakeScheduler, count: Int) {
        for i in 0..<count {
            let q = scheduler.nextQuestion(currentSettings: settings)
            XCTAssertEqual(q, .fresh, "Question \(i) should be fresh during advance")
            scheduler.recordCompletion(
                seed: UInt64(10000 + Int.random(in: 0...999999)),
                settings: settings,
                hadErrors: false,
                mistakeId: nil,
                sourceName: nil
            )
        }
    }
}

extension NextQuestion: Equatable {
    public static func == (lhs: NextQuestion, rhs: NextQuestion) -> Bool {
        switch (lhs, rhs) {
        case (.fresh, .fresh):
            return true
        case (.reask(let s1, _, let m1), .reask(let s2, _, let m2)):
            return s1 == s2 && m1 == m2
        default:
            return false
        }
    }
}
