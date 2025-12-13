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
    @Published var settings: PracticeSettingsSnapshot

    private let midiService: MIDIService
    private let sequenceGenerator: SequenceGenerator
    private let playbackScheduler: PlaybackScheduler
    private var cancellables: Set<AnyCancellable> = []

    init(
        midiService: MIDIService,
        sequenceGenerator: SequenceGenerator = SequenceGenerator(),
        settings: PracticeSettingsSnapshot = PracticeSettingsSnapshot()
    ) {
        self.midiService = midiService
        self.sequenceGenerator = sequenceGenerator
        self.playbackScheduler = PlaybackScheduler(midiService: midiService)
        self.settings = settings
        bind()
    }

    func selectOutput(id: MIDIUniqueID) {
        guard let endpoint = availableOutputs.first(where: { $0.id == id }) else { return }
        midiService.selectOutput(endpoint)
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
        let sequence = sequenceGenerator.generate(settings: settings, seed: seed)
        DispatchQueue.main.async {
            self.currentSequence = sequence
        }
        schedulePlayback(for: sequence)
    }

    func replay() {
        guard let sequence = currentSequence else { return }
        schedulePlayback(for: sequence)
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
            .assign(to: \.availableOutputs, on: self)
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
    }

    private func schedulePlayback(for sequence: MelodySequence) {
        DispatchQueue.main.async {
            self.isPlaying = true
        }

        playbackScheduler.play(sequence: sequence) { [weak self] in
            DispatchQueue.main.async {
                self?.isPlaying = false
            }
        }
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
