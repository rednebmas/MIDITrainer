import XCTest
@testable import MIDITrainer

final class SpacedMistakeSchedulerTests: XCTestCase {
    private func makeSettings() -> PracticeSettingsSnapshot {
        PracticeSettingsSnapshot(
            key: Key(root: .c),
            scaleType: .major,
            excludedDegrees: [],
            allowedOctaves: [4],
            melodyLength: 2,
            bpm: 80
        )
    }
    
    func testNewMistakeUsesSharedInitialClearance() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let db = try Database(path: tempURL.path)
        let repository = MistakeQueueRepository(db: db)
        let scheduler = SpacedMistakeScheduler(repository: repository)
        let settings = makeSettings()
        
        scheduler.recordCompletion(seed: 123, settings: settings, hadErrors: true, mistakeId: nil)
        
        guard let mistake = scheduler.queueSnapshot.first else {
            XCTFail("Expected mistake to be queued")
            return
        }
        
        XCTAssertEqual(mistake.minimumClearanceDistance, QueuedMistake.initialClearanceDistance)
        XCTAssertEqual(mistake.currentClearanceDistance, QueuedMistake.initialClearanceDistance)
        XCTAssertEqual(mistake.questionsSinceQueued, 0)
        
        // Ensure persisted values match the runtime defaults on a fresh load
        let reloadedRepository = MistakeQueueRepository(db: db)
        let reloadedScheduler = SpacedMistakeScheduler(repository: reloadedRepository)
        
        XCTAssertEqual(reloadedScheduler.queueSnapshot.first?.minimumClearanceDistance, QueuedMistake.initialClearanceDistance)
        XCTAssertEqual(reloadedScheduler.queueSnapshot.first?.currentClearanceDistance, QueuedMistake.initialClearanceDistance)
    }
}
