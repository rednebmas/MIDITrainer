import Combine
import CoreMIDI
import Foundation

final class PracticeModel: ObservableObject {
    @Published var availableInputs: [MIDIEndpoint] = []
    @Published var connectedInputs: [MIDIEndpoint] = []
    @Published var availableOutputs: [MIDIEndpoint] = []
    @Published private(set) var selectedOutputID: MIDIUniqueID?
    @Published private(set) var recentEvents: [String] = []
    @Published private(set) var currentSequence: MelodySequence?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var awaitingNoteIndex: Int?
    @Published var settings: PracticeSettingsSnapshot
    @Published private(set) var heldNotesCount: Int = 0

    private let midiService: MIDIService
    private let engine: PracticeEngine
    private let settingsStore: SettingsStore
    private var cancellables: Set<AnyCancellable> = []
    private var heldNotes: Set<UInt8> = []

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
            replayHotkeyEnabled: { settingsStore.replayHotkeyEnabled }
        )
        settingsStore.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                self?.settings = newSettings
            }
            .store(in: &cancellables)
        bind()
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

    func toggleInput(id: MIDIUniqueID) {
        guard let endpoint = availableInputs.first(where: { $0.id == id }) else { return }
        if connectedInputs.contains(where: { $0.id == id }) {
            midiService.disconnectInput(endpoint)
        } else {
            midiService.connectInput(endpoint)
        }
    }

    func refreshEndpoints() {
        midiService.refreshEndpoints()
    }

    func sendTestNote() {
        let note: UInt8 = 60 // middle C
        midiService.send(noteOn: note, velocity: 96)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) { [weak midiService] in
            midiService?.send(noteOff: note)
        }
    }

    func playQuestion(seed: UInt64? = nil) {
        engine.playQuestion(settings: settings, seed: seed)
    }

    func replay() {
        engine.replay()
    }

    /// Attempts to auto-select the last used MIDI output if no output is currently selected
    private func autoSelectLastOutputIfNeeded(outputs: [MIDIEndpoint]) {
        // Only auto-select if we don't already have a selection
        guard selectedOutputID == nil, !outputs.isEmpty else { return }
        
        // Try to match by ID first (most reliable)
        if let lastID = settingsStore.lastSelectedOutputID,
           let matchingEndpoint = outputs.first(where: { $0.id == lastID }) {
            midiService.selectOutput(matchingEndpoint)
            connectMatchingInput(for: matchingEndpoint)
            return
        }
        
        // Fall back to matching by name (Bluetooth devices may get new IDs)
        if let lastName = settingsStore.lastSelectedOutputName,
           let matchingEndpoint = outputs.first(where: { $0.name == lastName }) {
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
            .map { $0?.id }
            .receive(on: DispatchQueue.main)
            .assign(to: \.selectedOutputID, on: self)
            .store(in: &cancellables)

        midiService.noteEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.record(event: event)
            }
            .store(in: &cancellables)

        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                switch state {
                case .idle:
                    self.isPlaying = false
                    self.awaitingNoteIndex = nil
                case .playing(let sequence):
                    self.isPlaying = true
                    self.currentSequence = sequence
                    self.awaitingNoteIndex = nil
                case .awaitingInput(let sequence, let expectedIndex):
                    self.isPlaying = false
                    self.currentSequence = sequence
                    self.awaitingNoteIndex = expectedIndex
                case .completed(let sequence):
                    self.isPlaying = false
                    self.currentSequence = sequence
                    self.awaitingNoteIndex = nil
                }
            }
            .store(in: &cancellables)

        midiService.noteEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.trackHeld(event: event)
                self?.record(event: event)
            }
            .store(in: &cancellables)
    }

    private func trackHeld(event: MIDINoteEvent) {
        switch event {
        case .noteOn(let noteNumber, _):
            heldNotes.insert(noteNumber)
        case .noteOff(let noteNumber):
            heldNotes.remove(noteNumber)
        }
        heldNotesCount = heldNotes.count
    }

    private func record(event: MIDINoteEvent) {
        let description: String
        switch event {
        case .noteOn(let noteNumber, let velocity):
            description = "Note On \(noteNumber) v\(velocity)"
        case .noteOff(let noteNumber):
            description = "Note Off \(noteNumber)"
        }

        recentEvents = Array(([description] + recentEvents).prefix(5))
    }
}
