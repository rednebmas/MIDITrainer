import Combine
import CoreMIDI
import Foundation

struct SchedulerDebugEntry: Identifiable, Equatable {
    let id: Int64
    let seed: UInt64
    let minimumClearanceDistance: Int
    let currentClearanceDistance: Int
    let questionsSinceQueued: Int
    let remainingUntilDue: Int
    let isDue: Bool
    let isActive: Bool
}

enum SequenceFeedback {
    case perfect    // First attempt, no errors ever
    case correct    // Got it right, but had errors on previous attempts
    case tryAgain   // Made errors, will replay
}

final class PracticeModel: ObservableObject {
    @Published var availableInputs: [MIDIEndpoint] = []
    @Published var connectedInputs: [MIDIEndpoint] = []
    @Published var availableOutputs: [MIDIEndpoint] = []
    @Published private(set) var selectedOutputID: MIDIUniqueID?
    @Published private(set) var currentSequence: MelodySequence?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var awaitingNoteIndex: Int?
    @Published var settings: PracticeSettingsSnapshot
    @Published private(set) var errorNoteIndex: Int?
    @Published private(set) var isReplaying: Bool = false
    @Published private(set) var firstTryAccuracy: FirstTryAccuracy?
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var questionsAnsweredToday: Int = 0
    @Published private(set) var dailyGoal: Int = 30
    @Published private(set) var latestFeedback: SequenceFeedback?
    @Published private(set) var selectedOutputName: String?
    @Published private(set) var pendingMistakeCount: Int = 0
    @Published private(set) var questionsUntilNextReask: Int?
    @Published private(set) var schedulerDebugEntries: [SchedulerDebugEntry] = []


    private let midiService: MIDIService
    private let engine: PracticeEngine
    private let settingsStore: SettingsStore
    let schedulingCoordinator: SchedulingCoordinator
    private let statsRepository: StatsRepository
    private let statsQueue = DispatchQueue(label: "com.sambender.miditrainer.practice.stats", qos: .userInitiated)
    private var cancellables: Set<AnyCancellable> = []

    init(
        midiService: MIDIService,
        settingsStore: SettingsStore,
        sequenceGenerator: SequenceGenerator = SequenceGenerator()
    ) {
        self.midiService = midiService
        self.settingsStore = settingsStore
        self.settings = settingsStore.settings
        let playbackScheduler = PlaybackScheduler(midiService: midiService)
        let feedbackService = FeedbackService(midiService: midiService)

        let database: Database
        do {
            database = try Database()
        } catch {
            fatalError("Failed to open database: \(error)")
        }

        let settingsRepo = SettingsSnapshotRepository(db: database)
        let sessionRepo = SessionRepository(db: database)
        let sequenceRepo = SequenceRepository(db: database)
        let attemptRepo = AttemptRepository(db: database)
        let mistakeQueueRepo = MistakeQueueRepository(db: database)
        self.statsRepository = StatsRepository(db: database)
        
        // Create the scheduling coordinator with persisted mode
        self.schedulingCoordinator = SchedulingCoordinator(
            initialMode: settingsStore.schedulerMode,
            repository: mistakeQueueRepo,
            onModeChange: { newMode in
                settingsStore.schedulerMode = newMode
            }
        )

        self.engine = PracticeEngine(
            midiService: midiService,
            sequenceGenerator: sequenceGenerator,
            playbackScheduler: playbackScheduler,
            scoringService: ScoringService(),
            feedbackService: feedbackService,
            settingsRepository: settingsRepo,
            sessionRepository: sessionRepo,
            sequenceRepository: sequenceRepo,
            attemptRepository: attemptRepo,
            feedbackSettings: { settingsStore.feedback },
            replayHotkeyEnabled: { settingsStore.replayHotkeyEnabled },
            schedulingCoordinator: schedulingCoordinator
        )
        settingsStore.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                self?.settings = newSettings
                self?.refreshFirstTryAccuracy()
            }
            .store(in: &cancellables)
        bind()
        bindStats()
        bindScheduler()
        refreshFirstTryAccuracy()
    }

    private func bindStats() {
        settingsStore.$currentStreak
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentStreak, on: self)
            .store(in: &cancellables)

        settingsStore.$questionsAnsweredToday
            .receive(on: DispatchQueue.main)
            .assign(to: \.questionsAnsweredToday, on: self)
            .store(in: &cancellables)

        settingsStore.$dailyGoal
            .receive(on: DispatchQueue.main)
            .assign(to: \.dailyGoal, on: self)
            .store(in: &cancellables)
    }

    private func bindScheduler() {
        schedulingCoordinator.$pendingCount
            .receive(on: DispatchQueue.main)
            .assign(to: \.pendingMistakeCount, on: self)
            .store(in: &cancellables)

        schedulingCoordinator.$questionsUntilNextReask
            .receive(on: DispatchQueue.main)
            .assign(to: \.questionsUntilNextReask, on: self)
            .store(in: &cancellables)

        Publishers.CombineLatest(
            schedulingCoordinator.$queueSnapshot,
            schedulingCoordinator.$activeMistakeId
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] queue, activeId in
            let entries = queue.map { mistake -> SchedulerDebugEntry in
                let remaining = max(mistake.currentClearanceDistance - mistake.questionsSinceQueued, 0)
                return SchedulerDebugEntry(
                    id: mistake.id,
                    seed: mistake.seed,
                    minimumClearanceDistance: mistake.minimumClearanceDistance,
                    currentClearanceDistance: mistake.currentClearanceDistance,
                    questionsSinceQueued: mistake.questionsSinceQueued,
                    remainingUntilDue: remaining,
                    isDue: mistake.isDue,
                    isActive: mistake.id == activeId
                )
            }
            self?.schedulerDebugEntries = entries
        }
        .store(in: &cancellables)
    }

    func clearMistakeQueue() {
        schedulingCoordinator.clearQueue()
    }

    func selectOutput(id: MIDIUniqueID) {
        guard let endpoint = availableOutputs.first(where: { $0.id == id }) else { return }
        midiService.selectOutput(endpoint)
        // Persist the selection
        settingsStore.lastSelectedOutputID = endpoint.id
        settingsStore.lastSelectedOutputName = endpoint.name
        
        // Also connect the matching input (same device name) for bidirectional MIDI
        connectMatchingInput(for: endpoint)
    }
    
    /// Connects the input that matches the selected output by name
    private func connectMatchingInput(for outputEndpoint: MIDIEndpoint) {
        // Disconnect any previously connected inputs
        for connectedInput in connectedInputs {
            midiService.disconnectInput(connectedInput)
        }
        
        // Find and connect the input with the same name as the output
        if let matchingInput = availableInputs.first(where: { $0.name == outputEndpoint.name }) {
            midiService.connectInput(matchingInput)
        }
    }

    func refreshEndpoints() {
        midiService.refreshEndpoints()
    }

    func playQuestion(seed: UInt64? = nil) {
        isReplaying = false
        engine.playQuestion(settings: settings, seed: seed)
        errorNoteIndex = nil
    }

    func replay() {
        isReplaying = true
        errorNoteIndex = nil
        engine.replay()
    }

    /// Attempts to auto-select the last used MIDI output if no output is currently selected
    private func autoSelectLastOutputIfNeeded(outputs: [MIDIEndpoint]) {
        // Only auto-select if we don't already have a selection
        guard selectedOutputID == nil, !outputs.isEmpty else { return }

        // Try to match by ID first (most reliable), but skip offline devices
        if let lastID = settingsStore.lastSelectedOutputID,
           let matchingEndpoint = outputs.first(where: { $0.id == lastID && !$0.isOffline }) {
            midiService.selectOutput(matchingEndpoint)
            connectMatchingInput(for: matchingEndpoint)
            return
        }

        // Fall back to matching by name (Bluetooth devices may get new IDs), skip offline
        if let lastName = settingsStore.lastSelectedOutputName,
           let matchingEndpoint = outputs.first(where: { $0.name == lastName && !$0.isOffline }) {
            midiService.selectOutput(matchingEndpoint)
            connectMatchingInput(for: matchingEndpoint)
            // Update the stored ID to the new one
            settingsStore.lastSelectedOutputID = matchingEndpoint.id
            return
        }
    }

    private func bind() {
        midiService.availableInputsPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.availableInputs, on: self)
            .store(in: &cancellables)

        midiService.connectedInputsPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.connectedInputs, on: self)
            .store(in: &cancellables)

        midiService.availableOutputsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] outputs in
                guard let self else { return }
                self.availableOutputs = outputs
                self.autoSelectLastOutputIfNeeded(outputs: outputs)
            }
            .store(in: &cancellables)

        midiService.selectedOutputPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] endpoint in
                self?.selectedOutputID = endpoint?.id
                self?.selectedOutputName = endpoint?.name
            }
            .store(in: &cancellables)

        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle:
                    self.isPlaying = false
                    self.isReplaying = false
                    self.awaitingNoteIndex = nil
                case .playing(let sequence):
                    self.isPlaying = true
                    // keep isReplaying as set by caller
                    self.currentSequence = sequence
                    self.awaitingNoteIndex = nil
                    self.errorNoteIndex = nil
                case .awaitingInput(let sequence, let expectedIndex):
                    self.isPlaying = false
                    self.isReplaying = false
                    self.currentSequence = sequence
                    self.awaitingNoteIndex = expectedIndex
                case .completed(let sequence):
                    self.isPlaying = false
                    self.isReplaying = false
                    self.currentSequence = sequence
                    self.awaitingNoteIndex = nil
                    self.handleSequenceCompleted()
                    self.refreshFirstTryAccuracy()
                }
            }
            .store(in: &cancellables)

        midiService.noteEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.evaluateMistake(event: event)
            }
            .store(in: &cancellables)
    }

    private func evaluateMistake(event: MIDINoteEvent) {
        guard case let .noteOn(noteNumber, _) = event else { return }
        guard let expectedIndex = awaitingNoteIndex,
              let sequence = currentSequence,
              expectedIndex < sequence.notes.count else {
            errorNoteIndex = nil
            return
        }
        let expectedNote = sequence.notes[expectedIndex].midiNoteNumber
        if noteNumber == expectedNote {
            errorNoteIndex = nil
        } else {
            errorNoteIndex = expectedIndex
        }
    }

    private func handleSequenceCompleted() {
        // Check engine state for whether this attempt had errors
        // The engine tracks madeErrorInCurrentSequence (resets each attempt)
        // and hadErrorsInSequence (persists across replays for same sequence)
        let currentAttemptHadErrors = engine.hadErrorsInSequence && errorNoteIndex != nil

        // If the current attempt completed without errors
        if errorNoteIndex == nil {
            if engine.hadErrorsInSequence {
                // Got it right, but had errors on previous attempts
                settingsStore.incrementQuestionsAnswered()
                latestFeedback = .correct
            } else {
                // Perfect - first attempt, no errors ever
                settingsStore.incrementStreak()
                settingsStore.incrementQuestionsAnswered()
                latestFeedback = .perfect
            }
        } else {
            // Current attempt had errors - will replay
            settingsStore.resetStreak()
            latestFeedback = .tryAgain
        }

        // Clear feedback after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.latestFeedback = nil
        }
    }

    private func refreshFirstTryAccuracy() {
        let snapshot = settings
        statsQueue.async { [weak self] in
            guard let self else { return }
            let result = try? self.statsRepository.firstTryAccuracy(for: snapshot, limit: 20)
            DispatchQueue.main.async {
                self.firstTryAccuracy = result
            }
        }
    }
}
