import Foundation
import Combine

/// Coordinates question scheduling, managing the active scheduler and mode switching.
final class SchedulingCoordinator: ObservableObject {
    @Published private(set) var mode: SchedulerMode
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var questionsUntilNextReask: Int?
    @Published private(set) var queueSnapshot: [QueuedMistake] = []
    @Published private(set) var activeMistakeId: Int64?
    
    private var activeScheduler: QuestionScheduler
    private let spacedScheduler: SpacedMistakeScheduler
    private let randomScheduler: RandomScheduler
    private let onModeChange: (SchedulerMode) -> Void
    
    init(
        initialMode: SchedulerMode,
        repository: MistakeQueueRepository,
        onModeChange: @escaping (SchedulerMode) -> Void
    ) {
        self.mode = initialMode
        self.onModeChange = onModeChange
        self.spacedScheduler = SpacedMistakeScheduler(repository: repository)
        self.randomScheduler = RandomScheduler()
        
        switch initialMode {
        case .spacedMistakes:
            self.activeScheduler = spacedScheduler
        case .random:
            self.activeScheduler = randomScheduler
        }
        
        updatePublishedState()
    }
    
    /// Switches to a new scheduling mode.
    func setMode(_ newMode: SchedulerMode) {
        guard newMode != mode else { return }
        mode = newMode
        
        switch newMode {
        case .spacedMistakes:
            activeScheduler = spacedScheduler
        case .random:
            activeScheduler = randomScheduler
        }
        activeMistakeId = nil
        
        onModeChange(newMode)
        updatePublishedState()
    }
    
    /// Returns the next question to present.
    func nextQuestion(currentSettings: PracticeSettingsSnapshot) -> NextQuestion {
        let result = activeScheduler.nextQuestion(currentSettings: currentSettings)
        switch result {
        case .fresh:
            activeMistakeId = nil
        case .reask(_, _, let mistakeId):
            activeMistakeId = mistakeId
        }
        updatePublishedState()
        return result
    }
    
    /// Records the completion of a sequence.
    func recordCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, mistakeId: Int64?) {
        activeScheduler.recordCompletion(seed: seed, settings: settings, hadErrors: hadErrors, mistakeId: mistakeId)
        // Only clear activeMistakeId if there were no errors (sequence passed).
        // If there were errors, a replay will happen and we're still testing this mistake.
        if !hadErrors {
            activeMistakeId = nil
        }
        updatePublishedState()
    }
    
    /// Clears all pending mistakes from the queue.
    func clearQueue() {
        spacedScheduler.clearQueue()
        activeMistakeId = nil
        updatePublishedState()
    }
    
    private func updatePublishedState() {
        pendingCount = activeScheduler.pendingCount
        questionsUntilNextReask = activeScheduler.questionsUntilNextReask
        queueSnapshot = activeScheduler.queueSnapshot
    }
}
