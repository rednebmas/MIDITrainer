import Foundation

enum FeedbackMode: String, CaseIterable, Codable {
    case none
    case rootNote
    case rootTriad
}

struct FeedbackSettings: Codable, Equatable {
    var mode: FeedbackMode = .none
}

final class FeedbackService {
    private let midiService: MIDIService
    private let queue = DispatchQueue(label: "com.sambender.miditrainer.feedback")

    var channel: Int = 0

    init(midiService: MIDIService) {
        self.midiService = midiService
    }

    func playSequenceSuccess(for key: Key, settings: FeedbackSettings) {
        guard settings.mode != .none else { return }
        let feedbackChannel = channel
        queue.async { [weak self] in
            guard let self else { return }
            switch settings.mode {
            case .none:
                return
            case .rootNote:
                if let root = self.rootMidiNote(for: key) {
                    self.send(note: root, chord: [root], channel: feedbackChannel)
                }
            case .rootTriad:
                if let triad = self.rootTriad(for: key) {
                    self.send(note: triad.first ?? 0, chord: triad, channel: feedbackChannel)
                }
            }
        }
    }

    private func send(note: UInt8, chord: [UInt8], channel: Int) {
        for midiNote in chord {
            midiService.send(noteOn: midiNote, velocity: 90, channel: channel)
        }
        let releaseDelay = DispatchTime.now() + 0.4
        queue.asyncAfter(deadline: releaseDelay) { [weak self] in
            for midiNote in chord {
                self?.midiService.send(noteOff: midiNote, channel: channel)
            }
        }
    }

    private func rootMidiNote(for key: Key) -> UInt8? {
        Scale(key: key, type: .major).midiNoteNumber(for: .i, octave: 4)
    }

    private func rootTriad(for key: Key) -> [UInt8]? {
        let scale = Scale(key: key, type: .major)
        guard
            let root = scale.midiNoteNumber(for: .i, octave: 4),
            let third = scale.midiNoteNumber(for: .iii, octave: 4),
            let fifth = scale.midiNoteNumber(for: .v, octave: 4)
        else { return nil }
        return [root, third, fifth]
    }
}
