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
        XCTAssertEqual(q1, .fresh(seed: nil))

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)

        XCTAssertEqual(scheduler.pendingCount, 1)
        let snapshot = scheduler.queueSnapshot
        XCTAssertEqual(snapshot[0].seed, 100)
        XCTAssertEqual(snapshot[0].requiredClearance(clearance: 3, minPasses: 3), 9, "Default minPasses=3 puts the requirement at 3 × clearance")
        XCTAssertEqual(snapshot[0].currentClearance, 3)
        XCTAssertEqual(snapshot[0].questionsWaited, 0)
    }

    // MARK: - Re-ask becomes due after enough fresh questions

    func testReaskBecomesDueAfterClearance() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        for seed in UInt64(200)...201 {
            let q = scheduler.nextQuestion(currentSettings: settings)
            XCTAssertEqual(q, .fresh(seed: nil))
            scheduler.recordCompletion(seed: seed, settings: settings, hadErrors: false, mistakeId: nil, sourceName: nil)
        }
        XCTAssertEqual(scheduler.queueSnapshot[0].questionsWaited, 2)

        let q = scheduler.nextQuestion(currentSettings: settings)
        XCTAssertEqual(q, .fresh(seed: nil))
        scheduler.recordCompletion(seed: 202, settings: settings, hadErrors: false, mistakeId: nil, sourceName: nil)

        let next = scheduler.nextQuestion(currentSettings: settings)
        if case .reask(let seed, _, let id) = next {
            XCTAssertEqual(seed, 100)
            XCTAssertEqual(id, mistakeId)
        } else {
            XCTFail("Expected reask, got fresh")
        }
    }

    // MARK: - Failure resets currentClearance

    func testReaskFailureResetsCurrentClearance() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        XCTAssertEqual(scheduler.queueSnapshot[0].currentClearance, 3)

        // Fail first re-ask
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        let reask1 = scheduler.nextQuestion(currentSettings: settings)
        guard case .reask(_, _, let id1) = reask1 else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: id1, sourceName: nil)

        let after1 = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(after1.requiredClearance(clearance: 3, minPasses: 3), 9, "2 failures: requirement = 3 × max(3, 2) = 9 (floor held)")
        XCTAssertEqual(after1.currentClearance, 3, "current should RESET to base clearance")
        XCTAssertEqual(after1.questionsWaited, 0)

        // Fail second re-ask
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        let reask2 = scheduler.nextQuestion(currentSettings: settings)
        guard case .reask(_, _, let id2) = reask2 else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: id2, sourceName: nil)

        let after2 = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(after2.requiredClearance(clearance: 3, minPasses: 3), 9, "3 failures: requirement = 3 × max(3, 3) = 9")
        XCTAssertEqual(after2.currentClearance, 3, "current should RESET to base clearance again")

        // Fail third re-ask
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        let reask3 = scheduler.nextQuestion(currentSettings: settings)
        guard case .reask(_, _, let id3) = reask3 else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: id3, sourceName: nil)

        let after3 = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(after3.requiredClearance(clearance: 3, minPasses: 3), 12, "4 failures: requirement = 3 × max(3, 4) = 12")
        XCTAssertEqual(after3.currentClearance, 3, "current always resets to base on failure")
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
            XCTAssertEqual(entry.currentClearance, 3,
                           "current should always be base clearance after failure")
        }

        let final = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(final.requiredClearance(clearance: 3, minPasses: 3), 33,
                       "11 failures: requirement = 3 × max(3, 11) = 33")
        XCTAssertEqual(final.currentClearance, 3,
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
        XCTAssertEqual(updated.requiredClearance(clearance: 5, minPasses: 3), 15, "2 failures, clearance=5: requirement = 5 × max(3, 2) = 15")
        XCTAssertEqual(updated.currentClearance, 5)
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
        XCTAssertEqual(updated.requiredClearance(clearance: 5, minPasses: 3), 20, "4 failures, clearance=5 at last failure: requirement = 5 × max(3, 4) = 20")
        XCTAssertEqual(updated.currentClearance, 5)
        XCTAssertEqual(updated.totalFailures, Optional(4), "Failure count should track actual failures, not be derived from spacing values")
    }

    // MARK: - Failure steps back by clearance (floor at base)

    func testFailureStepsBackByClearanceFromHighGap() {
        // minPasses=5 so the card can accumulate passes without clearing.
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 }, minPassesProvider: { 5 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id
        XCTAssertEqual(scheduler.queueSnapshot[0].requiredClearance(clearance: 3, minPasses: 5), 15, "floor 5: 3 × 5 = 15")

        // Three successful passes: current 3 → 6 → 9 → 12 (none clear; requirement=15)
        for expectedAfter in [6, 9, 12] {
            let gap = scheduler.queueSnapshot.first { $0.id == mistakeId }!.currentClearance
            advanceFreshQuestions(scheduler: scheduler, count: gap)
            guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
            scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid, sourceName: nil)
            XCTAssertEqual(scheduler.queueSnapshot.first { $0.id == mistakeId }!.currentClearance, expectedAfter)
        }

        // Now fail from current=12. Step-back: max(3, 12-3) = 9.
        advanceFreshQuestions(scheduler: scheduler, count: 12)
        guard case .reask(_, _, let ridFail) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: ridFail, sourceName: nil)

        let afterFail = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(afterFail.currentClearance, 9,
                       "Failure should step current back by one clearance unit (12 − 3 = 9), not reset to base")
        XCTAssertEqual(afterFail.totalFailures, Optional(2), "totalFailures still increments on failure")
        XCTAssertEqual(afterFail.requiredClearance(clearance: 3, minPasses: 5), 15, "requirement derivation unchanged: max(5, 2) × 3 = 15")
    }

    func testFailureAtBaseStaysAtBase() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id
        XCTAssertEqual(scheduler.queueSnapshot[0].currentClearance, 3)

        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid, sourceName: nil)

        let after = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(after.currentClearance, 3, "max(3, 3-3) = 3 — stays at base floor")
        XCTAssertEqual(after.totalFailures, Optional(2), "totalFailures still bumps")
    }

    // MARK: - Mixed results: failure resets progress

    func testFailureAfterSuccessResetsCurrentClearance() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        // Fail re-ask twice: min=9 (floor), current=3
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
        XCTAssertEqual(afterPass.currentClearance, 6, "current bumped on success")
        XCTAssertEqual(afterPass.requiredClearance(clearance: 3, minPasses: 3), 9, "requirement unchanged on success (still 3 failures)")

        // Fail next re-ask: current should reset back to 3, min bumps to 12 (4 failures)
        advanceFreshQuestions(scheduler: scheduler, count: 6)
        guard case .reask(_, _, let rid4) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid4, sourceName: nil)

        let afterFail = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(afterFail.currentClearance, 3, "current resets to base on failure")
        XCTAssertEqual(afterFail.requiredClearance(clearance: 3, minPasses: 3), 12, "4 failures: requirement = 3 × max(3, 4) = 12")
    }

    // MARK: - Clearance floor (new behavior: minPasses default 3)

    func testOneFailureRequiresThreeSuccessfulPasses() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id
        XCTAssertEqual(scheduler.queueSnapshot[0].requiredClearance(clearance: 3, minPasses: 3), 9, "floor: 3 × max(3, 1) = 9")

        // Pass 1: current=3, check 3 >= 9 NO → bump to 6
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid1) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid1, sourceName: nil)
        XCTAssertEqual(scheduler.pendingCount, 1, "Still queued after pass 1")
        XCTAssertEqual(scheduler.queueSnapshot[0].currentClearance, 6)

        // Pass 2: current=6, check 6 >= 9 NO → bump to 9
        advanceFreshQuestions(scheduler: scheduler, count: 6)
        guard case .reask(_, _, let rid2) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid2, sourceName: nil)
        XCTAssertEqual(scheduler.pendingCount, 1, "Still queued after pass 2")
        XCTAssertEqual(scheduler.queueSnapshot[0].currentClearance, 9)

        // Pass 3: current=9, 9 >= 9 YES → cleared
        advanceFreshQuestions(scheduler: scheduler, count: 9)
        guard case .reask(_, _, let rid3) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid3, sourceName: nil)
        XCTAssertEqual(scheduler.pendingCount, 0, "Cleared after 3 passes")
        XCTAssertNil(scheduler.queueSnapshot.first { $0.id == mistakeId })
    }

    func testTwoFailuresStillRequiresThreeSuccessfulPasses() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid1) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid1, sourceName: nil)

        XCTAssertEqual(scheduler.queueSnapshot.first { $0.id == mistakeId }!.requiredClearance(clearance: 3, minPasses: 3), 9,
                       "2 failures: floor holds the requirement at 3 × 3 = 9, not 3 × 2 = 6")

        // Three passes still needed
        let expectedCurrents = [6, 9]
        for expected in expectedCurrents {
            let gap = scheduler.queueSnapshot.first { $0.id == mistakeId }!.currentClearance
            advanceFreshQuestions(scheduler: scheduler, count: gap)
            guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
            scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid, sourceName: nil)
            XCTAssertEqual(scheduler.pendingCount, 1)
            XCTAssertEqual(scheduler.queueSnapshot.first { $0.id == mistakeId }!.currentClearance, expected)
        }

        advanceFreshQuestions(scheduler: scheduler, count: 9)
        guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid, sourceName: nil)
        XCTAssertEqual(scheduler.pendingCount, 0, "Cleared on 3rd pass")
    }

    func testFourFailuresRequiresFourSuccessfulPasses() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        for _ in 0..<3 {
            advanceFreshQuestions(scheduler: scheduler, count: 3)
            guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
            scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid, sourceName: nil)
        }
        let afterFails = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(afterFails.totalFailures, Optional(4))
        XCTAssertEqual(afterFails.requiredClearance(clearance: 3, minPasses: 3), 12, "4 failures > floor 3: requirement = 3 × 4 = 12")

        // Three sub-clearing passes (current: 3 → 6 → 9 → 12)
        let expectedCurrents = [6, 9, 12]
        for expected in expectedCurrents {
            let gap = scheduler.queueSnapshot.first { $0.id == mistakeId }!.currentClearance
            advanceFreshQuestions(scheduler: scheduler, count: gap)
            guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
            scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid, sourceName: nil)
            XCTAssertEqual(scheduler.pendingCount, 1)
            XCTAssertEqual(scheduler.queueSnapshot.first { $0.id == mistakeId }!.currentClearance, expected)
        }

        // Final pass clears: current=12, 12 >= 12 YES
        advanceFreshQuestions(scheduler: scheduler, count: 12)
        guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid, sourceName: nil)
        XCTAssertEqual(scheduler.pendingCount, 0, "Cleared on 4th pass")
    }

    // MARK: - Configurable minPasses

    func testMinPassesOfOneDisablesFloor() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 }, minPassesProvider: { 1 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let snap = scheduler.queueSnapshot[0]
        XCTAssertEqual(snap.requiredClearance(clearance: 3, minPasses: 1), 3, "minPasses=1 reverts to no-floor behavior")
        XCTAssertEqual(snap.currentClearance, 3)

        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid, sourceName: nil)

        XCTAssertEqual(scheduler.pendingCount, 0, "Single pass clears when floor is 1")
    }

    func testMinPassesOfFiveRequiresFivePasses() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 }, minPassesProvider: { 5 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id
        XCTAssertEqual(scheduler.queueSnapshot[0].requiredClearance(clearance: 3, minPasses: 5), 15, "floor 5: 3 × 5 = 15")

        // Four sub-clearing passes: 3 → 6 → 9 → 12 → 15
        for _ in 0..<4 {
            let gap = scheduler.queueSnapshot.first { $0.id == mistakeId }!.currentClearance
            advanceFreshQuestions(scheduler: scheduler, count: gap)
            guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
            scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid, sourceName: nil)
            XCTAssertEqual(scheduler.pendingCount, 1)
        }
        XCTAssertEqual(scheduler.queueSnapshot.first { $0.id == mistakeId }!.currentClearance, 15)

        // 5th pass clears
        advanceFreshQuestions(scheduler: scheduler, count: 15)
        guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid, sourceName: nil)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testChangingMinPassesAppliesImmediately() {
        var floor = 3
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 }, minPassesProvider: { floor })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id
        XCTAssertEqual(scheduler.queueSnapshot[0].requiredClearance(clearance: 3, minPasses: floor), 9)

        floor = 5

        XCTAssertEqual(scheduler.queueSnapshot.first { $0.id == mistakeId }!.requiredClearance(clearance: 3, minPasses: floor), 15,
                       "Changing minPasses applies immediately — the requirement is derived, never stored")

        // Passing twice brings current to 9, but min is now 15 — not cleared
        for _ in 0..<2 {
            let gap = scheduler.queueSnapshot.first { $0.id == mistakeId }!.currentClearance
            advanceFreshQuestions(scheduler: scheduler, count: gap)
            guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
            scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: false, mistakeId: rid, sourceName: nil)
            XCTAssertEqual(scheduler.pendingCount, 1)
        }
        XCTAssertEqual(scheduler.queueSnapshot.first { $0.id == mistakeId }!.currentClearance, 9,
                       "current at 9 but derived min is 15 — still queued")
    }

    func testMinPassesAtOrBelowTotalFailuresIsNoop() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 }, minPassesProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        for _ in 0..<4 {
            advanceFreshQuestions(scheduler: scheduler, count: 3)
            guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
            scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid, sourceName: nil)
        }
        let final = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(final.totalFailures, Optional(5))
        XCTAssertEqual(final.requiredClearance(clearance: 3, minPasses: 3), 15, "5 failures > floor 3: requirement = 3 × 5 = 15")
    }

    // MARK: - Load queue preserves failure reset

    func testLoadQueuePreservesCurrentBelowMin() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        // Fail a fresh question, then fail the re-ask (current resets to 3, min=9 with floor)
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id
        advanceFreshQuestions(scheduler: scheduler, count: 3)
        guard case .reask(_, _, let rid) = scheduler.nextQuestion(currentSettings: settings) else { return XCTFail("Expected reask") }
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: rid, sourceName: nil)

        let before = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(before.currentClearance, 3, "current should be base after failure")

        // Simulate app restart by creating a new scheduler from the same DB
        let reloaded = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })
        let after = reloaded.queueSnapshot.first { $0.id == mistakeId }!

        XCTAssertEqual(after.currentClearance, 3,
                       "loadQueue must NOT boost current up to the requirement — failure reset must survive restart")
        XCTAssertEqual(after.totalFailures, Optional(2), "Persisted failure count should survive reload")
    }

    func testLoadQueueCapsCurrentAboveRequirement() {
        // Simulate stale data: current above the derived requirement
        let mistake = try! repo.insert(seed: 999, settings: settings, sourceName: nil, clearance: 3)
        try! repo.update(
            id: mistake.id,
            currentClearance: 50,
            totalFailures: 10,
            questionsWaited: 0
        )

        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })
        let loaded = scheduler.queueSnapshot.first { $0.id == mistake.id }!

        XCTAssertEqual(loaded.currentClearance, 30,
                       "current above the requirement (3 × max(3, 10) = 30) should be clamped down")
    }

    // MARK: - Defer (skip due card)

    func testDeferMistakeResetsCounter() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        advanceFreshQuestions(scheduler: scheduler, count: 3)
        XCTAssertTrue(scheduler.queueSnapshot[0].isDue, "Should be due after 3 fresh questions")

        scheduler.deferMistake(id: mistakeId)

        let after = scheduler.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(after.questionsWaited, 0, "Defer should reset counter")
        XCTAssertFalse(after.isDue, "Deferred mistake should no longer be due")
    }

    func testDeferPersistsAcrossReload() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })
        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let mistakeId = scheduler.queueSnapshot[0].id

        advanceFreshQuestions(scheduler: scheduler, count: 3)
        scheduler.deferMistake(id: mistakeId)

        let reloaded = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })
        let after = reloaded.queueSnapshot.first { $0.id == mistakeId }!
        XCTAssertEqual(after.questionsWaited, 0, "Defer must persist across reload")
        XCTAssertFalse(after.isDue)
    }

    func testDeferredMistakeIsSkippedInNextQuestion() {
        let scheduler = SpacedMistakeScheduler(repository: repo, clearanceProvider: { 3 })

        scheduler.recordCompletion(seed: 100, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let firstId = scheduler.queueSnapshot[0].id
        scheduler.recordCompletion(seed: 200, settings: settings, hadErrors: true, mistakeId: nil, sourceName: nil)
        let secondId = scheduler.queueSnapshot.last!.id

        // Drive the counters without asserting fresh (id=1 would become due partway through)
        for seed in UInt64(1000)...1002 {
            scheduler.recordCompletion(seed: seed, settings: settings, hadErrors: false, mistakeId: nil, sourceName: nil)
        }
        XCTAssertTrue(scheduler.queueSnapshot.allSatisfy { $0.isDue }, "Both should be due")

        scheduler.deferMistake(id: firstId)

        let next = scheduler.nextQuestion(currentSettings: settings)
        guard case .reask(_, _, let returnedId) = next else {
            return XCTFail("Expected reask for the non-deferred mistake")
        }
        XCTAssertEqual(returnedId, secondId, "Deferred mistake should be skipped in favor of the other due mistake")
    }

    // MARK: - Helpers

    private func advanceFreshQuestions(scheduler: SpacedMistakeScheduler, count: Int) {
        for i in 0..<count {
            let q = scheduler.nextQuestion(currentSettings: settings)
            XCTAssertEqual(q, .fresh(seed: nil), "Question \(i) should be fresh during advance")
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
