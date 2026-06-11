import XCTest
@testable import MIDITrainer

final class AdaptiveSchedulerTests: XCTestCase {
    private var db: Database!
    private var mistakeRepo: MistakeQueueRepository!
    private var fragmentRepo: FragmentQueueRepository!
    private var immediateDrills = false
    private var settings = PracticeSettingsSnapshot(melodySourceType: .random)

    override func setUp() {
        super.setUp()
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).sqlite"
        db = try! Database(path: path)
        mistakeRepo = MistakeQueueRepository(db: db)
        fragmentRepo = FragmentQueueRepository(db: db)
        immediateDrills = false
    }

    private func makeScheduler() -> AdaptiveScheduler {
        AdaptiveScheduler(
            mistakeRepository: mistakeRepo,
            fragmentQueue: AdaptiveFragmentQueue(repository: fragmentRepo, octaveMatters: { true }),
            statsRepository: StatsRepository(db: db),
            targetAccuracy: { 0.70 },
            clearance: { 3 },
            immediateDrills: { [unowned self] in self.immediateDrills }
        )
    }

    private func report(
        _ question: AskedQuestion,
        seed: UInt64? = nil,
        notes: [UInt8],
        failed: Set<Int> = [],
        sourceName: String? = nil
    ) -> CompletionReport {
        CompletionReport(
            seed: seed,
            settings: settings,
            hadErrors: !failed.isEmpty,
            question: question,
            sourceName: sourceName,
            notes: notes,
            firstAttemptFailedIndices: failed
        )
    }

    private func passFresh(_ scheduler: AdaptiveScheduler, seed: UInt64) {
        scheduler.record(report(.fresh, seed: seed, notes: [60, 62, 64]))
    }

    // MARK: - Cold start

    func testColdStartServesSeededFreshQuestion() {
        let scheduler = makeScheduler()
        guard case .fresh(let seed) = scheduler.nextQuestion(currentSettings: settings) else {
            return XCTFail("Expected fresh question")
        }
        XCTAssertNotNil(seed, "adaptive fresh questions carry a difficulty-targeted seed")
    }

    // MARK: - Failure queues parent + fragments

    func testFailedFreshMelodyQueuesParentAndFragment() {
        let scheduler = makeScheduler()
        scheduler.record(report(.fresh, seed: 100, notes: [60, 64, 67], failed: [1], sourceName: "Dark Horse"))

        XCTAssertEqual(scheduler.queueSnapshot.count, 1)
        XCTAssertEqual(scheduler.queueSnapshot[0].seed, 100)
        XCTAssertEqual(scheduler.pendingCount, 2, "one melody + one fragment")
        XCTAssertEqual(scheduler.debugSnapshot.fragments.count, 1)
        XCTAssertEqual(scheduler.debugSnapshot.gatedParentIds, [scheduler.queueSnapshot[0].id])
    }

    func testIndexZeroOnlyFailureQueuesUngatedParent() {
        let scheduler = makeScheduler()
        scheduler.record(report(.fresh, seed: 100, notes: [60, 64, 67], failed: [0]))

        XCTAssertEqual(scheduler.queueSnapshot.count, 1)
        XCTAssertTrue(scheduler.debugSnapshot.fragments.isEmpty)

        for seed in UInt64(200)...202 {
            passFresh(scheduler, seed: seed)
        }
        guard case .reask(let seed, _, _) = scheduler.nextQuestion(currentSettings: settings) else {
            return XCTFail("Ungated parent should rescue after base clearance")
        }
        XCTAssertEqual(seed, 100)
    }

    // MARK: - Immediate drills toggle

    func testImmediateDrillsServedInFailureOrderWhenEnabled() {
        immediateDrills = true
        let scheduler = makeScheduler()
        scheduler.record(report(.fresh, seed: 100, notes: [60, 64, 67, 72], failed: [1, 3]))

        guard case .fragment(let first) = scheduler.nextQuestion(currentSettings: settings) else {
            return XCTFail("Expected immediate drill")
        }
        XCTAssertEqual(first.midiNotes, [60, 64])
        XCTAssertEqual(first.label, "↑M3 drill")
        scheduler.record(report(.fragment(fragmentId: first.fragmentId), notes: first.midiNotes))

        guard case .fragment(let second) = scheduler.nextQuestion(currentSettings: settings) else {
            return XCTFail("Expected second immediate drill")
        }
        XCTAssertEqual(second.midiNotes, [67, 72])
        XCTAssertEqual(second.label, "↑P4 drill")
    }

    func testNoImmediateDrillWhenDisabled() {
        let scheduler = makeScheduler()
        scheduler.record(report(.fresh, seed: 100, notes: [60, 64, 67], failed: [1]))

        guard case .fresh = scheduler.nextQuestion(currentSettings: settings) else {
            return XCTFail("Fragment is not yet due and parent is gated — expected fresh")
        }
    }

    // MARK: - Full lifecycle: spacing, streak, rescue

    func testFragmentSpacingStreakAndRescueLifecycle() {
        let scheduler = makeScheduler()
        scheduler.record(report(.fresh, seed: 100, notes: [60, 64, 67], failed: [1], sourceName: "Dark Horse"))
        let parentId = scheduler.queueSnapshot[0].id

        var drillsCompleted = 0
        var freshSeed: UInt64 = 200
        var questionsAsked = 0

        while drillsCompleted < 3 {
            questionsAsked += 1
            XCTAssertLessThan(questionsAsked, 20, "lifecycle should converge")
            switch scheduler.nextQuestion(currentSettings: settings) {
            case .fragment(let drill):
                XCTAssertEqual(drill.midiNotes, [60, 64])
                XCTAssertEqual(drill.label, "↑M3 drill from Dark Horse")
                scheduler.record(report(.fragment(fragmentId: drill.fragmentId), notes: drill.midiNotes))
                drillsCompleted += 1
            case .fresh:
                passFresh(scheduler, seed: freshSeed)
                freshSeed += 1
            case .reask:
                XCTFail("Parent must stay gated while its fragment is open")
            }
        }

        XCTAssertTrue(scheduler.debugSnapshot.fragments.isEmpty, "streak of 3 clears the fragment")
        XCTAssertEqual(scheduler.queueSnapshot[0].questionsSinceQueued, 0, "clearing the last fragment arms the rescue")

        for _ in 0..<3 {
            guard case .fresh = scheduler.nextQuestion(currentSettings: settings) else {
                return XCTFail("Rescue should wait one clearance gap after arming")
            }
            passFresh(scheduler, seed: freshSeed)
            freshSeed += 1
        }

        guard case .reask(let seed, _, let mistakeId) = scheduler.nextQuestion(currentSettings: settings) else {
            return XCTFail("Expected rescue re-ask")
        }
        XCTAssertEqual(seed, 100)
        XCTAssertEqual(mistakeId, parentId)

        scheduler.record(report(.reask(mistakeId: mistakeId), seed: 100, notes: [60, 64, 67]))
        XCTAssertEqual(scheduler.pendingCount, 0, "passing the rescue is the only way out of the queue")
    }

    func testFailedFragmentResetsStreak() {
        let scheduler = makeScheduler()
        scheduler.record(report(.fresh, seed: 100, notes: [60, 64], failed: [1]))
        let fragmentId = scheduler.debugSnapshot.fragments[0].id

        scheduler.record(report(.fragment(fragmentId: fragmentId), notes: [60, 64]))
        XCTAssertEqual(scheduler.debugSnapshot.fragments[0].consecutiveCorrect, 1)

        scheduler.record(report(.fragment(fragmentId: fragmentId), notes: [60, 64], failed: [1]))
        XCTAssertEqual(scheduler.debugSnapshot.fragments[0].consecutiveCorrect, 0)
        XCTAssertEqual(scheduler.debugSnapshot.fragments[0].totalFailures, 2)
    }

    // MARK: - Rescue failure re-gates without escalation

    func testFailedRescueRegatesWithoutEscalation() {
        let scheduler = makeScheduler()
        scheduler.record(report(.fresh, seed: 100, notes: [60, 64, 67], failed: [0]))
        let parent = scheduler.queueSnapshot[0]

        for seed in UInt64(200)...202 {
            passFresh(scheduler, seed: seed)
        }
        guard case .reask(_, _, let mistakeId) = scheduler.nextQuestion(currentSettings: settings) else {
            return XCTFail("Expected rescue")
        }

        scheduler.record(report(.reask(mistakeId: mistakeId), seed: 100, notes: [60, 64, 67], failed: [2]))

        let after = scheduler.queueSnapshot[0]
        XCTAssertEqual(after.questionsSinceQueued, 0)
        XCTAssertEqual(after.totalFailures, 2)
        XCTAssertEqual(after.currentClearanceDistance, parent.currentClearanceDistance, "no escalation in adaptive mode")
        XCTAssertEqual(scheduler.debugSnapshot.fragments.count, 1, "failed rescue re-gates with fresh fragments")
        XCTAssertEqual(scheduler.debugSnapshot.gatedParentIds, [mistakeId])
    }

    // MARK: - Dedupe across parents

    func testSharedIdentityFragmentsClearTogether() {
        let scheduler = makeScheduler()
        scheduler.record(report(.fresh, seed: 100, notes: [60, 64], failed: [1]))
        scheduler.record(report(.fresh, seed: 101, notes: [60, 64, 67], failed: [1]))
        XCTAssertEqual(scheduler.debugSnapshot.fragments.count, 2, "one row per parent")

        let fragmentId = scheduler.debugSnapshot.fragments[0].id
        scheduler.record(report(.fragment(fragmentId: fragmentId), notes: [60, 64]))

        for fragment in scheduler.debugSnapshot.fragments {
            XCTAssertEqual(fragment.consecutiveCorrect, 1, "results apply to every row sharing the identity")
            XCTAssertEqual(fragment.questionsSinceAsked, 0, "shared identity is never asked twice in a row")
        }
    }

    // MARK: - Key changes

    func testQueuedFragmentTransposesToCurrentKey() {
        immediateDrills = true
        let scheduler = makeScheduler()
        scheduler.record(report(.fresh, seed: 100, notes: [60, 64], failed: [1]))

        let dMajor = PracticeSettingsSnapshot(key: Key(root: .d), melodySourceType: .random)
        guard case .fragment(let drill) = scheduler.nextQuestion(currentSettings: dMajor) else {
            return XCTFail("Expected drill")
        }
        XCTAssertEqual(drill.midiNotes, [62, 66], "i→iii in octave 4 renders as D4→F#4 in D major")
    }

    // MARK: - Clear queue

    func testClearQueueEmptiesBothTables() throws {
        let scheduler = makeScheduler()
        scheduler.record(report(.fresh, seed: 100, notes: [60, 64], failed: [1]))
        scheduler.clearQueue()

        XCTAssertEqual(scheduler.pendingCount, 0)
        XCTAssertEqual(try mistakeRepo.loadAll().count, 0)
        XCTAssertEqual(try fragmentRepo.loadAll().count, 0)
    }
}
