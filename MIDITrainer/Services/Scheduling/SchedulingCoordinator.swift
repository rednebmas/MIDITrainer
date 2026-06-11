import Foundation
import Combine

/// Coordinates question scheduling, managing the active scheduler and mode switching.
final class SchedulingCoordinator: ObservableObject {
    @Published private(set) var mode: SchedulerMode
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var questionsUntilNextReask: Int?
    @Published private(set) var queueSnapshot: [QueuedMistake] = []
    @Published private(set) var activeMistakeId: Int64?
    @Published private(set) var activeFragmentId: Int64?
    @Published private(set) var adaptiveSnapshot: AdaptiveDebugSnapshot?

    private var activeScheduler: QuestionScheduler
    private let spacedScheduler: SpacedMistakeScheduler
    private let weaknessScheduler: WeaknessFocusedScheduler
    private let randomScheduler: RandomScheduler
    private let adaptiveScheduler: AdaptiveScheduler
    private let onModeChange: (SchedulerMode) -> Void

    init(
        initialMode: SchedulerMode,
        repository: MistakeQueueRepository,
        fragmentRepository: FragmentQueueRepository,
        statsRepository: StatsRepository,
        sequenceGenerator: SequenceGenerator = SequenceGenerator(),
        weaknessMatchExactSettings: @escaping () -> Bool = { false },
        spacedMistakeClearance: @escaping () -> Int = { 3 },
        spacedMistakeMinPasses: @escaping () -> Int = { 3 },
        adaptiveTargetAccuracy: @escaping () -> Double = { 0.70 },
        adaptiveImmediateDrills: @escaping () -> Bool = { false },
        octaveMatters: @escaping () -> Bool = { true },
        onModeChange: @escaping (SchedulerMode) -> Void
    ) {
        self.mode = initialMode
        self.onModeChange = onModeChange
        self.spacedScheduler = SpacedMistakeScheduler(
            repository: repository,
            clearanceProvider: spacedMistakeClearance,
            minPassesProvider: spacedMistakeMinPasses
        )
        self.weaknessScheduler = WeaknessFocusedScheduler(
            spacedScheduler: spacedScheduler,
            statsRepository: statsRepository,
            matchExactSettings: weaknessMatchExactSettings
        )
        self.randomScheduler = RandomScheduler()
        self.adaptiveScheduler = AdaptiveScheduler(
            mistakeRepository: repository,
            fragmentQueue: AdaptiveFragmentQueue(repository: fragmentRepository, octaveMatters: octaveMatters),
            statsRepository: statsRepository,
            seedPicker: DifficultyTargetedSeedPicker(generator: sequenceGenerator),
            targetAccuracy: adaptiveTargetAccuracy,
            clearance: spacedMistakeClearance,
            immediateDrills: adaptiveImmediateDrills
        )

        self.activeScheduler = randomScheduler
        self.activeScheduler = scheduler(for: initialMode)

        updatePublishedState()
    }

    private func scheduler(for mode: SchedulerMode) -> QuestionScheduler {
        switch mode {
        case .spacedMistakes: return spacedScheduler
        case .weaknessFocused: return weaknessScheduler
        case .random: return randomScheduler
        case .adaptive: return adaptiveScheduler
        }
    }

    /// Switches to a new scheduling mode.
    func setMode(_ newMode: SchedulerMode) {
        guard newMode != mode else { return }
        mode = newMode
        activeScheduler = scheduler(for: newMode)
        activeScheduler.reload()
        activeMistakeId = nil
        activeFragmentId = nil

        onModeChange(newMode)
        updatePublishedState()
    }

    /// Returns the next question to present.
    func nextQuestion(currentSettings: PracticeSettingsSnapshot) -> NextQuestion {
        let result = activeScheduler.nextQuestion(currentSettings: currentSettings)
        switch result {
        case .fresh:
            activeMistakeId = nil
            activeFragmentId = nil
        case .reask(_, _, let mistakeId):
            activeMistakeId = mistakeId
            activeFragmentId = nil
        case .fragment(let drill):
            activeMistakeId = nil
            activeFragmentId = drill.fragmentId
        }
        updatePublishedState()
        return result
    }

    /// Records the completion of a sequence.
    /// `activeMistakeId` is intentionally not cleared here — the id represents the mistake
    /// associated with the currently displayed sequence, and it stays set until `nextQuestion`
    /// transitions to the next question (or defer/clearQueue/setMode explicitly reset it).
    func recordCompletion(_ report: CompletionReport) {
        if let adaptive = activeScheduler as? AdaptiveScheduler {
            adaptive.record(report)
        } else if let seed = report.seed {
            activeScheduler.recordCompletion(
                seed: seed,
                settings: report.settings,
                hadErrors: report.hadErrors,
                mistakeId: report.question.mistakeId,
                sourceName: report.sourceName
            )
        }
        updatePublishedState()
    }

    func recordCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, mistakeId: Int64?, sourceName: String?) {
        recordCompletion(CompletionReport(
            seed: seed,
            settings: settings,
            hadErrors: hadErrors,
            question: mistakeId.map { .reask(mistakeId: $0) } ?? .fresh,
            sourceName: sourceName,
            notes: [],
            firstAttemptFailedIndices: []
        ))
    }
    
    /// Defers the currently active re-ask: resets its wait counter so it's no longer due.
    func deferCurrentMistake() {
        guard let id = activeMistakeId else { return }
        spacedScheduler.deferMistake(id: id)
        activeMistakeId = nil
        updatePublishedState()
    }

    /// Clears all pending mistakes and fragments (the schedulers share tables).
    func clearQueue() {
        spacedScheduler.clearQueue()
        adaptiveScheduler.clearQueue()
        activeMistakeId = nil
        activeFragmentId = nil
        updatePublishedState()
    }

    private func updatePublishedState() {
        pendingCount = activeScheduler.pendingCount
        questionsUntilNextReask = activeScheduler.questionsUntilNextReask
        queueSnapshot = activeScheduler.queueSnapshot
        adaptiveSnapshot = mode == .adaptive ? adaptiveScheduler.debugSnapshot : nil
    }
}
