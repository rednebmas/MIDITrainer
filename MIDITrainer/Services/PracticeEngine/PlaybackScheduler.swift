import Foundation

final class PlaybackScheduler {
    private let midiService: MIDIService
    private let queue = DispatchQueue(label: "com.sambender.miditrainer.playback")
    private var scheduledItems: [DispatchWorkItem] = []

    init(midiService: MIDIService) {
        self.midiService = midiService
    }

    func play(sequence: MelodySequence, velocity: UInt8 = 96, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            cancelScheduledLocked()

            let secondsPerBeat = 60.0 / Double(sequence.bpm)
            let lastEnd = scheduleNotes(sequence: sequence, secondsPerBeat: secondsPerBeat, velocity: velocity)
            scheduleCompletion(after: lastEnd, completion: completion)
        }
    }

    func cancelScheduled() {
        queue.async { [weak self] in
            self?.cancelScheduledLocked()
        }
    }

    private func scheduleNotes(sequence: MelodySequence, secondsPerBeat: Double, velocity: UInt8) -> Double {
        var lastEnd: Double = 0

        for note in sequence.notes {
            let startSeconds = note.startBeat * secondsPerBeat
            let durationSeconds = note.durationBeats * secondsPerBeat
            lastEnd = max(lastEnd, startSeconds + durationSeconds)

            let onItem = DispatchWorkItem { [weak self] in
                self?.midiService.send(noteOn: note.midiNoteNumber, velocity: velocity)
            }
            let offItem = DispatchWorkItem { [weak self] in
                self?.midiService.send(noteOff: note.midiNoteNumber)
            }

            scheduledItems.append(onItem)
            queue.asyncAfter(deadline: .now() + startSeconds, execute: onItem)

            scheduledItems.append(offItem)
            queue.asyncAfter(deadline: .now() + startSeconds + durationSeconds, execute: offItem)
        }

        return lastEnd
    }

    private func scheduleCompletion(after time: Double, completion: (() -> Void)?) {
        guard let completion else { return }

        let completionItem = DispatchWorkItem(block: completion)
        scheduledItems.append(completionItem)
        queue.asyncAfter(deadline: .now() + time, execute: completionItem)
    }

    private func cancelScheduledLocked() {
        scheduledItems.forEach { $0.cancel() }
        scheduledItems.removeAll()
    }
}
