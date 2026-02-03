import Combine
import CoreMIDI
import Foundation
import UIKit

struct SchedulerDebugEntry: Identifiable, Equatable {
    let id: Int64
    let seed: UInt64
    let sourceName: String?
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
    @Published private(set) var sequenceHistory: [SequenceHistoryEntry] = []
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var questionsAnsweredToday: Int = 0
    @Published private(set) var dailyGoal: Int = 30
    @Published private(set) var latestFeedback: SequenceFeedback?
    @Published private(set) var selectedOutputName: String?
    @Published private(set) var pendingMistakeCount: Int = 0
    @Published private(set) var questionsUntilNextReask: Int?
    @Published private(set) var schedulerDebugEntries: [SchedulerDebugEntry] = []
    @Published private(set) var useOnScreenKeyboard: Bool = false
    @Published private(set) var schedulerMode: SchedulerMode = .spacedMistakes
    @Published private(set) var weaknessDebugEntries: [WeaknessEntry] = []
    @Published private(set) var spacedMistakeClearance: Int = 3
    @Published private(set) var showChordSymbols: Bool = true
    @Published private(set) var showNoteOrbs: Bool = true
    @Published private(set) var isScanningMIDI: Bool = true
    @Published private(set) var currentDeviceSettings: DeviceSettings?
    @Published private(set) var keysAreHeld: Bool = false
    @Published private(set) var currentAttemptNumber: Int = 1

    var isMidiConnected: Bool {
        if useOnScreenKeyboard { return true }
        guard let outputID = selectedOutputID else { return false }
        return availableOutputs.first(where: { $0.id == outputID })?.isOffline == false
    }

    private let midiService: MIDIService
    private let engine: PracticeEngine
    private let settingsStore: SettingsStore
    let schedulingCoordinator: SchedulingCoordinator
    private let statsRepository: StatsRepository
    private let statsQueue = DispatchQueue(label: "com.sambender.miditrainer.practice.stats", qos: .userInitiated)
    private var cancellables: Set<AnyCancellable> = []
    private let pianoSamplePlayer = PianoSamplePlayer()

    init(
        midiService: MIDIService,
        settingsStore: SettingsStore,
        sequenceGenerator: SequenceGenerator = SequenceGenerator()
    ) {
        self.midiService = midiService
        self.settingsStore = settingsStore
        self.settings = settingsStore.settings
        let initialVolume = settingsStore.midiOutputVolume
        let playbackScheduler = PlaybackScheduler(
            midiService: midiService,
            samplePlayer: pianoSamplePlayer,
            useSamples: { [weak settingsStore] in
                guard let store = settingsStore else { return false }
                if store.useOnScreenKeyboard { return true }
                if let deviceName = store.lastSelectedOutputName {
                    return store.deviceSettings(for: deviceName).playSamplesForMIDIInput
                }
                return false
            },
            volumeProvider: { [weak settingsStore] in settingsStore?.midiOutputVolume ?? initialVolume }
        )

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
            statsRepository: self.statsRepository,
            weaknessMatchExactSettings: { settingsStore.weaknessMatchExactSettings },
            spacedMistakeClearance: { settingsStore.spacedMistakeClearance },
            onModeChange: { newMode in
                settingsStore.schedulerMode = newMode
            }
        )

        self.engine = PracticeEngine(
            midiService: midiService,
            sequenceGenerator: sequenceGenerator,
            playbackScheduler: playbackScheduler,
            scoringService: ScoringService(),
            settingsRepository: settingsRepo,
            sessionRepository: sessionRepo,
            sequenceRepository: sequenceRepo,
            attemptRepository: attemptRepo,
            statsRepository: self.statsRepository,
            replayHotkeyNote: { settingsStore.replayHotkeyNote },
            chordAccompanimentEnabled: { settingsStore.chordAccompanimentEnabled },
            chordLoopDuringInput: { settingsStore.chordLoopDuringInput },
            chordVoicingStyle: { settingsStore.chordVoicingStyle },
            chordVolumeRatio: { settingsStore.chordVolumeRatio },
            melodyMIDIChannel: { settingsStore.melodyMIDIChannel },
            chordMIDIChannel: { settingsStore.chordMIDIChannel },
            weightIntervalsByErrorRate: { settingsStore.weightIntervalsByErrorRate },
            octaveMatters: { settingsStore.octaveMatters },
            useOnScreenKeyboard: { settingsStore.useOnScreenKeyboard },
            currentSettingsProvider: { settingsStore.settings },
            schedulingCoordinator: schedulingCoordinator
        )
        settingsStore.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                guard let self else { return }
                let oldSettings = self.settings
                self.settings = newSettings

                // If melody source changed, clear the mistake queue and start fresh
                if oldSettings.melodySourceType != newSettings.melodySourceType {
                    self.schedulingCoordinator.clearQueue()

                    if case .active = self.engine.state {
                        self.playQuestion()
                    } else if case .completed = self.engine.state {
                        self.playQuestion()
                    }
                }

                self.refreshFirstTryAccuracy()
                self.refreshWeaknessEntries()
            }
            .store(in: &cancellables)

        // Initialize on-screen keyboard state
        useOnScreenKeyboard = settingsStore.useOnScreenKeyboard
        if useOnScreenKeyboard {
            selectedOutputName = "On-Screen Keyboard"
        }

        // Initialize display state
        showChordSymbols = settingsStore.showChordSymbols
        showNoteOrbs = settingsStore.showNoteOrbs

        bind()
        bindStats()
        bindScheduler()
        bindForegroundRefresh()
        refreshFirstTryAccuracy()
        refreshWeaknessEntries()
    }

    private func bindForegroundRefresh() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshFirstTryAccuracy()
            }
            .store(in: &cancellables)
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

        settingsStore.$showChordSymbols
            .receive(on: DispatchQueue.main)
            .assign(to: \.showChordSymbols, on: self)
            .store(in: &cancellables)

        settingsStore.$showNoteOrbs
            .receive(on: DispatchQueue.main)
            .assign(to: \.showNoteOrbs, on: self)
            .store(in: &cancellables)

        settingsStore.$spacedMistakeClearance
            .receive(on: DispatchQueue.main)
            .assign(to: \.spacedMistakeClearance, on: self)
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

        schedulingCoordinator.$mode
            .receive(on: DispatchQueue.main)
            .assign(to: \.schedulerMode, on: self)
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
                    sourceName: mistake.sourceName,
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

    private func refreshWeaknessEntries() {
        let snapshot = settings
        let matchExact = settingsStore.weaknessMatchExactSettings
        statsQueue.async { [weak self] in
            guard let self else { return }
            let entries = try? self.statsRepository.topWeaknesses(
                for: snapshot,
                limit: 20,
                matchExactSettings: matchExact
            )
            DispatchQueue.main.async {
                self.weaknessDebugEntries = entries ?? []
            }
        }
    }

    func clearMistakeQueue() {
        schedulingCoordinator.clearQueue()
    }

    func selectOutput(id: MIDIUniqueID) {
        guard let endpoint = availableOutputs.first(where: { $0.id == id }) else { return }
        midiService.selectOutput(endpoint)
        settingsStore.lastSelectedOutputID = endpoint.id
        settingsStore.lastSelectedOutputName = endpoint.name
        currentDeviceSettings = settingsStore.deviceSettings(for: endpoint.name)
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
        print("[MIDI] PracticeModel.refreshEndpoints() called")
        midiService.refreshEndpoints()
    }

    func setUseOnScreenKeyboard(_ enabled: Bool) {
        useOnScreenKeyboard = enabled
        settingsStore.useOnScreenKeyboard = enabled
        if enabled {
            selectedOutputName = "On-Screen Keyboard"
            currentDeviceSettings = nil
        } else if let output = availableOutputs.first(where: { $0.id == selectedOutputID }) {
            selectedOutputName = output.name
            currentDeviceSettings = settingsStore.deviceSettings(for: output.name)
        }
    }

    func updateCurrentDeviceSettings(_ settings: DeviceSettings) {
        guard let name = selectedOutputName, !useOnScreenKeyboard else { return }
        currentDeviceSettings = settings
        settingsStore.setDeviceSettings(settings, for: name)
    }

    func injectNoteOn(_ noteNumber: UInt8) {
        // Convert volume (0.0-1.0) to MIDI velocity (0-127)
        let velocity = UInt8(min(max(settingsStore.midiOutputVolume * 127.0, 0), 127))
        // Play sample for audio feedback
        if useOnScreenKeyboard {
            pianoSamplePlayer.play(midiNote: noteNumber, velocity: velocity)
        }
        // Inject event so the practice engine can evaluate it
        midiService.injectNoteEvent(.noteOn(noteNumber: noteNumber, velocity: velocity))
    }

    func injectNoteOff(_ noteNumber: UInt8) {
        midiService.injectNoteEvent(.noteOff(noteNumber: noteNumber))
    }

    func playQuestion(seed: UInt64? = nil) {
        isReplaying = false
        engine.playQuestion(settings: settings, seed: seed)
    }

    func replay() {
        isReplaying = true
        engine.replay()
    }

    func skip() {
        playQuestion()
    }

    private func autoSelectLastOutputIfNeeded(outputs: [MIDIEndpoint]) {
        print("[MIDI] autoSelectLastOutputIfNeeded() called with \(outputs.count) outputs")
        print("[MIDI]   Current selectedOutputID: \(String(describing: selectedOutputID))")
        print("[MIDI]   Saved lastSelectedOutputID: \(String(describing: settingsStore.lastSelectedOutputID))")
        print("[MIDI]   Saved lastSelectedOutputName: \(String(describing: settingsStore.lastSelectedOutputName))")
        for output in outputs {
            print("[MIDI]   Available: '\(output.name)' id=\(output.id) offline=\(output.isOffline)")
        }

        guard !outputs.isEmpty else {
            print("[MIDI]   Skipping: no outputs available")
            return
        }

        let currentDeviceOnline = selectedOutputID != nil &&
            outputs.contains(where: { $0.id == selectedOutputID && !$0.isOffline })

        guard !currentDeviceOnline else {
            print("[MIDI]   Skipping: current device is online")
            return
        }

        if let lastID = settingsStore.lastSelectedOutputID,
           let matchingEndpoint = outputs.first(where: { $0.id == lastID && !$0.isOffline }) {
            print("[MIDI]   Matched by ID: '\(matchingEndpoint.name)'")
            autoSelect(matchingEndpoint)
            return
        }

        if let lastName = settingsStore.lastSelectedOutputName,
           let matchingEndpoint = outputs.first(where: { $0.name == lastName && !$0.isOffline }) {
            print("[MIDI]   Matched by name: '\(matchingEndpoint.name)'")
            autoSelect(matchingEndpoint)
            settingsStore.lastSelectedOutputID = matchingEndpoint.id
            return
        }

        let realDevices = outputs.filter { endpoint in
            let name = endpoint.name.lowercased()
            let isSystemDevice = name.contains("network session") ||
                name.contains("garageband") ||
                name.contains("virtual") ||
                name.contains("atsequencer") ||
                name.contains("iac driver")
            return !endpoint.isOffline && !isSystemDevice
        }

        if realDevices.count == 1, let device = realDevices.first {
            print("[MIDI]   Auto-selecting only available real device: '\(device.name)'")
            autoSelect(device)
            settingsStore.lastSelectedOutputID = device.id
            settingsStore.lastSelectedOutputName = device.name
            return
        }

        if realDevices.count > 1 {
            print("[MIDI]   Multiple real devices available, not auto-selecting: \(realDevices.map(\.name))")
        } else {
            print("[MIDI]   No real devices found")
        }
    }

    private func autoSelect(_ endpoint: MIDIEndpoint) {
        midiService.selectOutput(endpoint)
        currentDeviceSettings = settingsStore.deviceSettings(for: endpoint.name)
        connectMatchingInput(for: endpoint)
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
                print("[MIDI] availableOutputsPublisher received \(outputs.count) outputs")
                self.availableOutputs = outputs
                self.autoSelectLastOutputIfNeeded(outputs: outputs)
            }
            .store(in: &cancellables)

        midiService.selectedOutputPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] endpoint in
                guard let self else { return }
                self.selectedOutputID = endpoint?.id
                self.selectedOutputName = endpoint?.name
                if let name = endpoint?.name, !self.useOnScreenKeyboard {
                    self.currentDeviceSettings = self.settingsStore.deviceSettings(for: name)
                } else {
                    self.currentDeviceSettings = nil
                }
            }
            .store(in: &cancellables)

        midiService.isScanningPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.isScanningMIDI, on: self)
            .store(in: &cancellables)

        midiService.noteEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self,
                      !self.useOnScreenKeyboard,
                      self.currentDeviceSettings?.playSamplesForMIDIInput == true,
                      case .noteOn(let noteNumber, let velocity) = event,
                      noteNumber != self.settingsStore.replayHotkeyNote else { return }
                self.pianoSamplePlayer.play(midiNote: noteNumber, velocity: velocity)
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
                    self.currentSequence = nil
                    self.awaitingNoteIndex = nil
                case .active(let sequence, let isPlayingBack):
                    self.isPlaying = isPlayingBack
                    self.currentSequence = sequence
                    self.awaitingNoteIndex = self.engine.currentInputIndex
                    // isReplaying is set by caller before triggering state change
                case .completed(let sequence, let hadErrors):
                    self.isPlaying = false
                    self.isReplaying = false
                    self.currentSequence = sequence
                    self.awaitingNoteIndex = nil
                    self.handleSequenceCompleted(hadErrorsInSequence: hadErrors)
                    self.refreshFirstTryAccuracy()
                    self.refreshWeaknessEntries()
                }
            }
            .store(in: &cancellables)

        engine.$currentInputIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                guard let self else { return }
                // Update awaitingNoteIndex when we have an active sequence
                if case .active = self.engine.state {
                    self.awaitingNoteIndex = index
                }
            }
            .store(in: &cancellables)

        engine.$errorNoteIndex
            .receive(on: DispatchQueue.main)
            .assign(to: \.errorNoteIndex, on: self)
            .store(in: &cancellables)

        engine.$keysAreHeld
            .receive(on: DispatchQueue.main)
            .assign(to: \.keysAreHeld, on: self)
            .store(in: &cancellables)

        engine.$currentAttemptNumber
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentAttemptNumber, on: self)
            .store(in: &cancellables)
    }

    private func handleSequenceCompleted(hadErrorsInSequence: Bool) {
        // madeErrorInCurrentAttempt resets each replay, hadErrorsInSequence persists
        let currentAttemptHadErrors = engine.madeErrorInCurrentAttempt

        // If the current attempt completed without errors (won't replay)
        if !currentAttemptHadErrors {
            if hadErrorsInSequence {
                // Got it right, but had errors on previous attempts - counts as 1 question
                settingsStore.incrementQuestionsAnswered()
                latestFeedback = .correct
            } else {
                // Perfect - first attempt, no errors ever
                settingsStore.incrementStreak()
                settingsStore.incrementQuestionsAnswered()
                latestFeedback = .perfect
            }
        } else {
            // Current attempt had errors - will replay, don't count yet
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
        let startOfToday = Calendar.current.startOfDay(for: Date())
        statsQueue.async { [weak self] in
            guard let self else { return }
            let accuracy = try? self.statsRepository.firstTryAccuracy(for: snapshot, limit: 1000, since: startOfToday)
            let history = try? self.statsRepository.sequenceHistory(for: snapshot, limit: 20)
            DispatchQueue.main.async {
                self.firstTryAccuracy = accuracy
                self.sequenceHistory = history ?? []
            }
        }
    }

    func buildDebugInfo() -> DebugInfo {
        let questionState = buildQuestionState()
        let settingsContext = buildSettingsContext()
        let attempts = engine.recentAttempts.map {
            DebugInfo.AttemptEntry(playedNote: $0.playedNote, expectedNote: $0.expectedNote, isCorrect: $0.isCorrect)
        }
        let sequenceInfo = buildSequenceInfo()
        return DebugInfo(questionState: questionState, settingsContext: settingsContext, recentAttempts: attempts, sequenceInfo: sequenceInfo)
    }

    private func buildQuestionState() -> DebugInfo.QuestionState {
        let totalNotes = currentSequence?.notes.count ?? 0
        let expectedNote: UInt8? = {
            guard let idx = awaitingNoteIndex, let seq = currentSequence, idx < seq.notes.count else { return nil }
            return seq.notes[idx].midiNoteNumber
        }()
        let isOctaveSensitive = settingsStore.octaveMatters && !useOnScreenKeyboard
        return DebugInfo.QuestionState(noteIndex: awaitingNoteIndex, totalNotes: totalNotes, expectedMidiNote: expectedNote, isOctaveSensitive: isOctaveSensitive)
    }

    private func buildSettingsContext() -> DebugInfo.SettingsContext {
        DebugInfo.SettingsContext(
            keyName: settings.key.root.displayName,
            scaleName: settings.scaleType.storageKey.capitalized,
            allowedOctaves: settings.allowedOctaves,
            octaveMatters: settingsStore.octaveMatters,
            useOnScreenKeyboard: useOnScreenKeyboard
        )
    }

    private func buildSequenceInfo() -> DebugInfo.SequenceInfo? {
        guard let sequence = currentSequence else { return nil }
        let seedOrName: String = {
            if let seed = engine.currentSeed { return String(seed) }
            if let name = sequence.sourceName { return name }
            return "unknown"
        }()
        return DebugInfo.SequenceInfo(seedOrName: seedOrName, midiNotes: sequence.notes.map(\.midiNoteNumber))
    }
}
