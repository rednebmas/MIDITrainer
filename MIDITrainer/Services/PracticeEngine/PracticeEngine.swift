import Combine
import Foundation

final class PracticeEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case playing(MelodySequence)
        case awaitingInput(sequence: MelodySequence, expectedIndex: Int)
        case completed(MelodySequence)
    }

    @Published private(set) var state: State = .idle

    private let midiService: MIDIService
    private let sequenceGenerator: SequenceGenerator
    private let playbackScheduler: PlaybackScheduler
    private let scoringService: ScoringService
    private let feedbackService: FeedbackService
    private let settingsRepository: SettingsSnapshotRepository
    private let sessionRepository: SessionRepository
    private let sequenceRepository: SequenceRepository
    private let attemptRepository: AttemptRepository
    private let feedbackSettings: () -> FeedbackSettings
    private let replayHotkeyEnabled: () -> Bool
    private let schedulingCoordinator: SchedulingCoordinator?
    private var cancellables: Set<AnyCancellable> = []

    private var activeSession: (id: Int64, settingsSnapshotId: Int64, settings: PracticeSettingsSnapshot)?
    private var currentSequenceIDs: PersistedSequenceIDs?
    private var lastCorrectExpected: UInt8?
    private var lastCorrectGuessed: UInt8?
    
    /// Tracks the current note index during playback+input phase
    private var currentInputIndex: Int = 0
    /// Tracks whether any mistake was made in the current attempt (resets on replay)
    @Published private(set) var madeErrorInCurrentAttempt: Bool = false
    /// Whether playback has finished (user can still input during playback)
    private var playbackFinished: Bool = false
    /// Tracks currently held MIDI notes for detecting when all keys are released
    private var heldNotes: Set<UInt8> = []
    /// Pending action to execute when all keys are released
    private var pendingCompletionAction: (() -> Void)?
    /// The seed used for the current sequence (for scheduler tracking)
    private var currentSeed: UInt64?
    /// If the current sequence is a re-ask, this is the mistake ID
    private var currentMistakeId: Int64?
    /// Whether we've already recorded a completion for the current sequence (to avoid duplicates on replays)
    private var hasRecordedCompletion: Bool = false
    /// Whether the user ever made an error on the current sequence (persists across replays)
    @Published private(set) var hadErrorsInSequence: Bool = false

    init(
        midiService: MIDIService,
        sequenceGenerator: SequenceGenerator,
        playbackScheduler: PlaybackScheduler,
        scoringService: ScoringService,
        feedbackService: FeedbackService,
        settingsRepository: SettingsSnapshotRepository,
        sessionRepository: SessionRepository,
        sequenceRepository: SequenceRepository,
        attemptRepository: AttemptRepository,
        feedbackSettings: @escaping () -> FeedbackSettings,
        replayHotkeyEnabled: @escaping () -> Bool,
        schedulingCoordinator: SchedulingCoordinator? = nil
    ) {
        self.midiService = midiService
        self.sequenceGenerator = sequenceGenerator
        self.playbackScheduler = playbackScheduler
        self.scoringService = scoringService
        self.feedbackService = feedbackService
        self.settingsRepository = settingsRepository
        self.sessionRepository = sessionRepository
        self.sequenceRepository = sequenceRepository
        self.attemptRepository = attemptRepository
        self.feedbackSettings = feedbackSettings
        self.replayHotkeyEnabled = replayHotkeyEnabled
        self.schedulingCoordinator = schedulingCoordinator
        bindMIDI()
    }

    func playQuestion(settings: PracticeSettingsSnapshot, seed: UInt64? = nil) {
        // Determine what question to play via the scheduler
        let questionToPlay: NextQuestion
        if let coordinator = schedulingCoordinator {
            questionToPlay = coordinator.nextQuestion(currentSettings: settings)
        } else {
            questionToPlay = .fresh
        }
        
        switch questionToPlay {
        case .fresh:
            let selectedSeed = seed ?? UInt64.random(in: .min ... .max)
            startSequence(settings: settings, seed: selectedSeed, mistakeId: nil)
        case .reask(let reaskSeed, let reaskSettings, let mistakeId):
            startSequence(settings: reaskSettings, seed: reaskSeed, mistakeId: mistakeId)
        }
    }
    
    private func startSequence(settings: PracticeSettingsSnapshot, seed: UInt64, mistakeId: Int64?) {
        do {
            let session = try ensureSession(for: settings)
            let sequence = sequenceGenerator.generate(settings: settings, seed: seed)
            let ids = try sequenceRepository.insert(sequence: sequence, sessionId: session.id, settingsSnapshotId: session.settingsSnapshotId)
            currentSequenceIDs = ids
            currentSeed = seed
            currentMistakeId = mistakeId
            hasRecordedCompletion = false
            hadErrorsInSequence = false
            lastCorrectExpected = nil
            lastCorrectGuessed = nil
            currentInputIndex = 0
            madeErrorInCurrentAttempt = false
            playbackFinished = false

            DispatchQueue.main.async { [weak self] in
                self?.state = .playing(sequence)
            }

            playbackScheduler.play(sequence: sequence) { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.playbackFinished = true
                    if case .playing(let seq) = self.state, self.currentInputIndex >= seq.notes.count {
                        self.handleSequenceCompleted(sequence: seq, settings: settings)
                    } else if case .playing(let seq) = self.state {
                        self.state = .awaitingInput(sequence: seq, expectedIndex: self.currentInputIndex)
                    }
                }
            }
        } catch {
            // For now we silently fail; future milestone can surface errors to the UI.
        }
    }

    private func bindMIDI() {
        midiService.noteEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .noteOn(let noteNumber, _):
                    self.heldNotes.insert(noteNumber)
                    if self.handleReplayHotkey(noteNumber: noteNumber) { return }
                    self.handle(noteOn: noteNumber)
                case .noteOff(let noteNumber):
                    self.heldNotes.remove(noteNumber)
                    self.checkPendingCompletionAction()
                }
            }
            .store(in: &cancellables)
    }
    
    /// Checks if all keys are released and executes pending action if so
    private func checkPendingCompletionAction() {
        guard heldNotes.isEmpty, let action = pendingCompletionAction else { return }
        pendingCompletionAction = nil
        action()
    }

    private func handleReplayHotkey(noteNumber: UInt8) -> Bool {
        guard replayHotkeyEnabled() else { return false }
        // A0 on an 88-key keyboard is MIDI note 21; use as replay hotkey.
        if noteNumber == 21 {
            replay()
            return true
        }
        return false
    }

    private func handle(noteOn noteNumber: UInt8) {
        // Get the current sequence from either playing or awaitingInput state
        let sequence: MelodySequence
        let expectedIndex: Int
        
        switch state {
        case .playing(let seq):
            sequence = seq
            expectedIndex = currentInputIndex
        case .awaitingInput(let seq, let idx):
            sequence = seq
            expectedIndex = idx
        default:
            return
        }
        
        guard expectedIndex < sequence.notes.count else { return }

        let expectedNote = sequence.notes[expectedIndex]
        let isCorrect = noteNumber == expectedNote.midiNoteNumber
        let scale = Scale(key: sequence.key, type: sequence.scaleType)

        let descriptor = scoringService.descriptor(
            expectedNote: expectedNote,
            guessedMidiNote: noteNumber,
            previousCorrectExpected: lastCorrectExpected,
            previousCorrectGuessed: lastCorrectGuessed,
            scale: scale,
            isCorrect: isCorrect
        )

        persistAttempt(descriptor: descriptor, sequence: sequence, noteIndex: expectedIndex)

        if isCorrect {
            lastCorrectExpected = expectedNote.midiNoteNumber
            lastCorrectGuessed = noteNumber
            let nextIndex = expectedIndex + 1
            currentInputIndex = nextIndex
            
            if nextIndex >= sequence.notes.count {
                // User finished the sequence
                if playbackFinished {
                    handleSequenceCompleted(sequence: sequence, settings: activeSession?.settings)
                }
                // If playback hasn't finished, the completion callback will handle it
            } else {
                // Update state to show progress (only if not in playing state)
                if case .awaitingInput = state {
                    state = .awaitingInput(sequence: sequence, expectedIndex: nextIndex)
                }
            }
        } else {
            // Record that an error was made
            madeErrorInCurrentAttempt = true
            hadErrorsInSequence = true
        }
    }
    
    private func handleSequenceCompleted(sequence: MelodySequence, settings: PracticeSettingsSnapshot?) {
        state = .completed(sequence)
        
        // Notify the scheduler of the completion (only once per sequence, not on replays)
        if !hasRecordedCompletion, let seed = currentSeed, let settings = settings {
            hasRecordedCompletion = true
            schedulingCoordinator?.recordCompletion(
                seed: seed,
                settings: settings,
                hadErrors: madeErrorInCurrentAttempt,
                mistakeId: currentMistakeId
            )
        }
        
        let delaySeconds = settings.map { 60.0 / Double($0.bpm) } ?? 0.5
        
        let action: () -> Void = { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
                guard let self else { return }
                if self.madeErrorInCurrentAttempt {
                    self.replayCurrentSequence(sequence: sequence, settings: settings)
                } else {
                    self.feedbackService.playSequenceSuccess(for: sequence.key, settings: self.feedbackSettings())
                    if let settings {
                        self.playQuestion(settings: settings)
                    }
                }
            }
        }
        
        // Wait for all keys to be released before triggering the delay
        if heldNotes.isEmpty {
            action()
        } else {
            pendingCompletionAction = action
        }
    }
    
    private func replayCurrentSequence(sequence: MelodySequence, settings: PracticeSettingsSnapshot?) {
        lastCorrectExpected = nil
        lastCorrectGuessed = nil
        currentInputIndex = 0
        madeErrorInCurrentAttempt = false
        playbackFinished = false

        state = .playing(sequence)

        playbackScheduler.play(sequence: sequence) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.playbackFinished = true
                if case .playing(let seq) = self.state, self.currentInputIndex >= seq.notes.count {
                    self.handleSequenceCompleted(sequence: seq, settings: settings)
                } else if case .playing(let seq) = self.state {
                    self.state = .awaitingInput(sequence: seq, expectedIndex: self.currentInputIndex)
                }
            }
        }
    }

    func replay() {
        let sequence: MelodySequence
        switch state {
        case .awaitingInput(let current, _), .completed(let current):
            sequence = current
        case .playing(let current):
            sequence = current
        default:
            return
        }

        replayCurrentSequence(sequence: sequence, settings: activeSession?.settings)
    }

    private func persistAttempt(descriptor: AttemptMetadata, sequence: MelodySequence, noteIndex: Int) {
        guard let currentSequenceIDs, let activeSession else { return }
        let melodyNoteId = noteIndex < currentSequenceIDs.noteIds.count ? currentSequenceIDs.noteIds[noteIndex] : nil

        DispatchQueue.global(qos: .utility).async { [attemptRepository] in
            try? attemptRepository.insertAttempt(
                metadata: descriptor,
                sessionId: activeSession.id,
                sequenceId: currentSequenceIDs.sequenceId,
                melodyNoteId: melodyNoteId,
                key: sequence.key,
                scaleType: sequence.scaleType
            )
        }
    }

    private func ensureSession(for settings: PracticeSettingsSnapshot) throws -> (id: Int64, settingsSnapshotId: Int64, settings: PracticeSettingsSnapshot) {
        if let activeSession, activeSession.settings == settings {
            return activeSession
        }

        let snapshotId = try settingsRepository.insert(snapshot: settings)
        let sessionId = try sessionRepository.startSession(settingsSnapshotId: snapshotId)
        let session = (id: sessionId, settingsSnapshotId: snapshotId, settings: settings)
        activeSession = session
        return session
    }
}
