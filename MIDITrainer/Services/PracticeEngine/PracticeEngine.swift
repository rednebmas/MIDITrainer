import Combine
import Foundation

final class PracticeEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case active(sequence: MelodySequence, isPlayingBack: Bool)
        /// Sequence completed. `hadErrors` indicates if user ever made an error (persists across replays).
        case completed(sequence: MelodySequence, hadErrors: Bool)
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
    private let statsRepository: StatsRepository?
    private let feedbackSettings: () -> FeedbackSettings
    private let replayHotkeyEnabled: () -> Bool
    private let chordAccompanimentEnabled: () -> Bool
    private let chordLoopDuringInput: () -> Bool
    private let chordVoicingStyle: () -> ChordVoicingStyle
    private let chordVolumeRatio: () -> Double
    private let melodyMIDIChannel: () -> Int
    private let chordMIDIChannel: () -> Int
    private let weightIntervalsByErrorRate: () -> Bool
    private let currentSettingsProvider: () -> PracticeSettingsSnapshot
    private let schedulingCoordinator: SchedulingCoordinator?
    private var cancellables: Set<AnyCancellable> = []

    private var activeSession: (id: Int64, settingsSnapshotId: Int64, settings: PracticeSettingsSnapshot)?
    private var currentSequenceIDs: PersistedSequenceIDs?
    private var lastCorrectExpected: UInt8?
    private var lastCorrectGuessed: UInt8?
    
    /// Tracks the current note index during playback+input phase
    @Published private(set) var currentInputIndex: Int = 0
    /// Index of the note where the most recent error occurred (nil if last input was correct)
    @Published private(set) var errorNoteIndex: Int?
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
        statsRepository: StatsRepository? = nil,
        feedbackSettings: @escaping () -> FeedbackSettings,
        replayHotkeyEnabled: @escaping () -> Bool,
        chordAccompanimentEnabled: @escaping () -> Bool = { true },
        chordLoopDuringInput: @escaping () -> Bool = { false },
        chordVoicingStyle: @escaping () -> ChordVoicingStyle = { .shell },
        chordVolumeRatio: @escaping () -> Double = { 0.5 },
        melodyMIDIChannel: @escaping () -> Int = { 0 },
        chordMIDIChannel: @escaping () -> Int = { 0 },
        weightIntervalsByErrorRate: @escaping () -> Bool = { false },
        currentSettingsProvider: @escaping () -> PracticeSettingsSnapshot,
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
        self.statsRepository = statsRepository
        self.feedbackSettings = feedbackSettings
        self.replayHotkeyEnabled = replayHotkeyEnabled
        self.chordAccompanimentEnabled = chordAccompanimentEnabled
        self.chordLoopDuringInput = chordLoopDuringInput
        self.chordVoicingStyle = chordVoicingStyle
        self.chordVolumeRatio = chordVolumeRatio
        self.melodyMIDIChannel = melodyMIDIChannel
        self.chordMIDIChannel = chordMIDIChannel
        self.weightIntervalsByErrorRate = weightIntervalsByErrorRate
        self.currentSettingsProvider = currentSettingsProvider
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
            // Stop any existing chord loop before starting a new sequence
            playbackScheduler.stopChordLoop()

            let session = try ensureSession(for: settings)

            // Fetch interval error rates if weighting is enabled and melody source is random
            let intervalErrorRates: [StatBucket]?
            if weightIntervalsByErrorRate(), settings.melodySourceType == .random, let statsRepo = statsRepository {
                let filter = StatsFilter.key(settings.key, settings.scaleType)
                intervalErrorRates = try? statsRepo.mistakeRateByInterval(filter: filter)
            } else {
                intervalErrorRates = nil
            }

            let sequence = sequenceGenerator.generate(settings: settings, seed: seed, intervalErrorRates: intervalErrorRates)
            let ids = try sequenceRepository.insert(sequence: sequence, sessionId: session.id, settingsSnapshotId: session.settingsSnapshotId)
            currentSequenceIDs = ids
            currentSeed = seed
            currentMistakeId = mistakeId
            hasRecordedCompletion = false
            hadErrorsInSequence = false
            lastCorrectExpected = nil
            lastCorrectGuessed = nil
            currentInputIndex = 0
            errorNoteIndex = nil
            madeErrorInCurrentAttempt = false
            playbackFinished = false

            DispatchQueue.main.async { [weak self] in
                self?.state = .active(sequence: sequence, isPlayingBack: true)
            }

            playSequenceWithChords(sequence: sequence, settings: settings)
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
        // Only process input in active state
        guard case .active(let sequence, _) = state else { return }
        guard currentInputIndex < sequence.notes.count else { return }

        let expectedNote = sequence.notes[currentInputIndex]
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

        persistAttempt(descriptor: descriptor, sequence: sequence, noteIndex: currentInputIndex)

        if isCorrect {
            errorNoteIndex = nil
            lastCorrectExpected = expectedNote.midiNoteNumber
            lastCorrectGuessed = noteNumber
            currentInputIndex += 1

            if currentInputIndex >= sequence.notes.count {
                // User finished the sequence
                if playbackFinished {
                    handleSequenceCompleted(sequence: sequence, settings: activeSession?.settings)
                }
                // If playback hasn't finished, the completion callback will handle it
            }
        } else {
            // Record that an error was made
            errorNoteIndex = currentInputIndex
            madeErrorInCurrentAttempt = true
            hadErrorsInSequence = true
        }
    }
    
    private func handleSequenceCompleted(sequence: MelodySequence, settings: PracticeSettingsSnapshot?) {
        // Stop chord looping when sequence completes
        playbackScheduler.stopChordLoop()

        state = .completed(sequence: sequence, hadErrors: hadErrorsInSequence)

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
                    self.feedbackService.channel = self.melodyMIDIChannel()
                    self.feedbackService.playSequenceSuccess(for: sequence.key, settings: self.feedbackSettings())
                    // Use fresh settings from provider to pick up any changes made during practice
                    let freshSettings = self.currentSettingsProvider()
                    self.playQuestion(settings: freshSettings)
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
        // Stop any existing chord loop before replay
        playbackScheduler.stopChordLoop()

        lastCorrectExpected = nil
        lastCorrectGuessed = nil
        currentInputIndex = 0
        errorNoteIndex = nil
        madeErrorInCurrentAttempt = false
        playbackFinished = false

        state = .active(sequence: sequence, isPlayingBack: true)

        playSequenceWithChords(sequence: sequence, settings: settings)
    }

    func replay() {
        let sequence: MelodySequence
        switch state {
        case .active(let current, _), .completed(sequence: let current, hadErrors: _):
            sequence = current
        default:
            return
        }

        replayCurrentSequence(sequence: sequence, settings: activeSession?.settings)
    }

    /// Configures and starts playback of a sequence with optional chord accompaniment.
    private func playSequenceWithChords(sequence: MelodySequence, settings: PracticeSettingsSnapshot?) {
        playbackScheduler.chordVoicingStyle = chordVoicingStyle()
        playbackScheduler.chordVolumeMultiplier = chordVolumeRatio()
        playbackScheduler.melodyChannel = melodyMIDIChannel()
        playbackScheduler.chordChannel = chordMIDIChannel()
        let chordsToPlay = chordAccompanimentEnabled() ? sequence.chords : nil

        playbackScheduler.play(sequence: sequence, chords: chordsToPlay) { [weak self] in
            self?.handlePlaybackFinished(settings: settings)
        }
    }

    /// Called when melody playback finishes - handles transition to input phase or completion.
    private func handlePlaybackFinished(settings: PracticeSettingsSnapshot?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.playbackFinished = true

            guard case .active(let sequence, _) = self.state else { return }

            if self.currentInputIndex >= sequence.notes.count {
                // User already finished input during playback
                self.handleSequenceCompleted(sequence: sequence, settings: settings)
            } else {
                // Transition to input phase
                self.state = .active(sequence: sequence, isPlayingBack: false)
                if let settings {
                    self.startChordLoopIfNeeded(sequence: sequence, settings: settings)
                }
            }
        }
    }

    /// Starts chord looping if the setting is enabled and the sequence has chords
    private func startChordLoopIfNeeded(sequence: MelodySequence, settings: PracticeSettingsSnapshot) {
        guard chordLoopDuringInput(),
              chordAccompanimentEnabled(),
              let chords = sequence.chords,
              !chords.isEmpty else {
            return
        }

        // Calculate loop duration based on the melody duration
        let secondsPerBeat = 60.0 / Double(settings.bpm)
        let loopDuration = sequence.notes.map { $0.startBeat + $0.durationBeats }.max() ?? 0
        let loopDurationSeconds = loopDuration * secondsPerBeat

        playbackScheduler.startChordLoop(
            chords: chords,
            bpm: settings.bpm,
            loopDuration: loopDurationSeconds
        )
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
