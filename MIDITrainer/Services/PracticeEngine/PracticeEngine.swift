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
    private let settingsRepository: SettingsSnapshotRepository
    private let sessionRepository: SessionRepository
    private let sequenceRepository: SequenceRepository
    private let attemptRepository: AttemptRepository
    private var cancellables: Set<AnyCancellable> = []

    private var activeSession: (id: Int64, settingsSnapshotId: Int64, settings: PracticeSettingsSnapshot)?
    private var currentSequenceIDs: PersistedSequenceIDs?
    private var lastCorrectExpected: UInt8?
    private var lastCorrectGuessed: UInt8?

    init(
        midiService: MIDIService,
        sequenceGenerator: SequenceGenerator,
        playbackScheduler: PlaybackScheduler,
        scoringService: ScoringService,
        settingsRepository: SettingsSnapshotRepository,
        sessionRepository: SessionRepository,
        sequenceRepository: SequenceRepository,
        attemptRepository: AttemptRepository
    ) {
        self.midiService = midiService
        self.sequenceGenerator = sequenceGenerator
        self.playbackScheduler = playbackScheduler
        self.scoringService = scoringService
        self.settingsRepository = settingsRepository
        self.sessionRepository = sessionRepository
        self.sequenceRepository = sequenceRepository
        self.attemptRepository = attemptRepository
        bindMIDI()
    }

    func playQuestion(settings: PracticeSettingsSnapshot, seed: UInt64? = nil) {
        do {
            let session = try ensureSession(for: settings)
            let sequence = sequenceGenerator.generate(settings: settings, seed: seed)
            let ids = try sequenceRepository.insert(sequence: sequence, sessionId: session.id, settingsSnapshotId: session.settingsSnapshotId)
            currentSequenceIDs = ids
            lastCorrectExpected = nil
            lastCorrectGuessed = nil

            DispatchQueue.main.async { [weak self] in
                self?.state = .playing(sequence)
            }

            playbackScheduler.play(sequence: sequence) { [weak self] in
                DispatchQueue.main.async {
                    self?.state = .awaitingInput(sequence: sequence, expectedIndex: 0)
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
                guard case let .noteOn(noteNumber, _) = event else { return }
                self?.handle(noteOn: noteNumber)
            }
            .store(in: &cancellables)
    }

    private func handle(noteOn noteNumber: UInt8) {
        guard case let .awaitingInput(sequence, expectedIndex) = state else { return }
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
            if nextIndex >= sequence.notes.count {
                DispatchQueue.main.async { [weak self] in
                    self?.state = .completed(sequence)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.state = .awaitingInput(sequence: sequence, expectedIndex: nextIndex)
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

        lastCorrectExpected = nil
        lastCorrectGuessed = nil

        DispatchQueue.main.async { [weak self] in
            self?.state = .playing(sequence)
        }

        playbackScheduler.play(sequence: sequence) { [weak self] in
            DispatchQueue.main.async {
                self?.state = .awaitingInput(sequence: sequence, expectedIndex: 0)
            }
        }
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
