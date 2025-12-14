import Foundation

final class PlaybackScheduler {
    private let midiService: MIDIService
    private let samplePlayer: PianoSamplePlayer?
    private let useSamples: () -> Bool
    private let volumeProvider: () -> Double
    private let queue = DispatchQueue(label: "com.sambender.miditrainer.playback")
    private var scheduledItems: [DispatchWorkItem] = []
    private var activeChordNotes: Set<UInt8> = []

    /// Chord voicing style (configurable)
    var chordVoicingStyle: ChordVoicingStyle = .shell

    /// Volume multiplier for chord accompaniment relative to melody (0.0-1.0)
    var chordVolumeMultiplier: Double = 0.5

    var melodyChannel: Int = 0
    var chordChannel: Int = 0

    init(
        midiService: MIDIService,
        samplePlayer: PianoSamplePlayer? = nil,
        useSamples: @escaping () -> Bool = { false },
        volumeProvider: @escaping () -> Double = { 0.75 }
    ) {
        self.midiService = midiService
        self.samplePlayer = samplePlayer
        self.useSamples = useSamples
        self.volumeProvider = volumeProvider
    }

    func play(sequence: MelodySequence, completion: (() -> Void)? = nil) {
        play(sequence: sequence, chords: nil, completion: completion)
    }

    func play(
        sequence: MelodySequence,
        chords: [PhraseChordEvent]?,
        completion: (() -> Void)? = nil
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            cancelScheduledLocked()
            stopAllChordNotes()

            // Convert volume (0.0-1.0) to MIDI velocity (0-127)
            let velocity = UInt8(min(max(self.volumeProvider() * 127.0, 0), 127))
            let secondsPerBeat = 60.0 / Double(sequence.bpm)
            let melodyEnd = scheduleNotes(sequence: sequence, secondsPerBeat: secondsPerBeat, velocity: velocity)

            // Schedule chord accompaniment if provided
            var lastEnd = melodyEnd
            if let chords = chords, !chords.isEmpty {
                let chordEnd = scheduleChords(
                    chords: chords,
                    phraseDuration: melodyEnd,
                    velocity: velocity
                )
                lastEnd = max(melodyEnd, chordEnd)
            }

            scheduleCompletion(after: lastEnd, completion: completion)
        }
    }

    func cancelScheduled() {
        queue.async { [weak self] in
            self?.cancelScheduledLocked()
            self?.stopAllChordNotes()
            self?.isLoopingChords = false
        }
    }

    /// Starts looping chord events continuously until stopped.
    /// - Parameters:
    ///   - chords: The chord events to loop
    ///   - bpm: BPM for timing calculations
    ///   - loopDuration: Duration of one loop in seconds
    func startChordLoop(chords: [PhraseChordEvent], bpm: Int, loopDuration: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            self.isLoopingChords = true
            self.loopingChords = chords
            self.loopBpm = bpm
            self.loopDuration = loopDuration
            self.scheduleChordLoop()
        }
    }

    /// Stops chord looping.
    func stopChordLoop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isLoopingChords = false
            self.loopingChords = nil
            self.cancelChordLoopItems()
            self.stopAllChordNotes()
        }
    }

    private var isLoopingChords = false
    private var loopingChords: [PhraseChordEvent]?
    private var loopBpm: Int = 80
    private var loopDuration: Double = 4.0
    private var chordLoopItems: [DispatchWorkItem] = []

    private func scheduleChordLoop() {
        guard isLoopingChords, let chords = loopingChords, !chords.isEmpty else { return }

        cancelChordLoopItems()

        let velocity = UInt8(min(max(volumeProvider() * 127.0 * chordVolumeMultiplier, 0), 127))

        scheduleChordEvents(
            chords: chords,
            duration: loopDuration,
            velocity: velocity,
            items: &chordLoopItems,
            guardCheck: { [weak self] in self?.isLoopingChords == true }
        )

        // Schedule next loop iteration
        let loopItem = DispatchWorkItem { [weak self] in
            guard let self, self.isLoopingChords else { return }
            self.scheduleChordLoop()
        }
        chordLoopItems.append(loopItem)
        queue.asyncAfter(deadline: .now() + loopDuration, execute: loopItem)
    }

    private func cancelChordLoopItems() {
        chordLoopItems.forEach { $0.cancel() }
        chordLoopItems.removeAll()
    }

    private func scheduleNotes(sequence: MelodySequence, secondsPerBeat: Double, velocity: UInt8) -> Double {
        var lastEnd: Double = 0

        for note in sequence.notes {
            let startSeconds = note.startBeat * secondsPerBeat
            let durationSeconds = note.durationBeats * secondsPerBeat
            lastEnd = max(lastEnd, startSeconds + durationSeconds)

            let onItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if self.useSamples(), let player = self.samplePlayer {
                    player.play(midiNote: note.midiNoteNumber, velocity: velocity)
                } else {
                    self.midiService.send(noteOn: note.midiNoteNumber, velocity: velocity, channel: self.melodyChannel)
                }
            }
            let offItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if !self.useSamples() {
                    self.midiService.send(noteOff: note.midiNoteNumber, channel: self.melodyChannel)
                }
                // Sample player handles note duration internally
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

    // MARK: - Chord Scheduling

    private func scheduleChords(
        chords: [PhraseChordEvent],
        phraseDuration: Double,
        velocity: UInt8
    ) -> Double {
        let chordVelocity = UInt8(Double(velocity) * chordVolumeMultiplier)

        return scheduleChordEvents(
            chords: chords,
            duration: phraseDuration,
            velocity: chordVelocity,
            items: &scheduledItems,
            guardCheck: nil
        )
    }

    /// Shared chord scheduling logic used by both one-shot and looping playback.
    /// - Parameters:
    ///   - chords: The chord events to schedule
    ///   - duration: Total duration for calculating last chord's length
    ///   - velocity: MIDI velocity for the chords
    ///   - items: The work item array to append to (scheduledItems or chordLoopItems)
    ///   - guardCheck: Optional closure that must return true for note-on to execute (used for looping)
    /// - Returns: The end time of the last scheduled chord
    @discardableResult
    private func scheduleChordEvents(
        chords: [PhraseChordEvent],
        duration: Double,
        velocity: UInt8,
        items: inout [DispatchWorkItem],
        guardCheck: (() -> Bool)?
    ) -> Double {
        let voicer = ChordVoicer(style: chordVoicingStyle, octave: 3)
        var lastEnd: Double = 0

        for (index, chord) in chords.enumerated() {
            guard let symbol = chord.chordSymbol,
                  let midiNotes = voicer.voicing(for: symbol) else {
                continue
            }

            let startTime = max(0, chord.offset)
            let endTime: Double
            if index + 1 < chords.count {
                endTime = max(startTime + 0.1, chords[index + 1].offset)
            } else {
                endTime = duration
            }
            let chordDuration = endTime - startTime
            guard chordDuration > 0 else { continue }

            lastEnd = max(lastEnd, startTime + chordDuration)

            // Schedule note on
            let onItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if let check = guardCheck, !check() { return }
                for note in midiNotes {
                    self.playChordNote(note, velocity: velocity)
                    self.activeChordNotes.insert(note)
                }
            }
            items.append(onItem)
            queue.asyncAfter(deadline: .now() + startTime, execute: onItem)

            // Schedule note off
            let offItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                for note in midiNotes {
                    self.stopChordNote(note)
                    self.activeChordNotes.remove(note)
                }
            }
            items.append(offItem)
            queue.asyncAfter(deadline: .now() + startTime + chordDuration, execute: offItem)
        }

        return lastEnd
    }

    private func playChordNote(_ note: UInt8, velocity: UInt8) {
        if useSamples(), let player = samplePlayer {
            player.play(midiNote: note, velocity: velocity)
        } else {
            midiService.send(noteOn: note, velocity: velocity, channel: chordChannel)
        }
    }

    private func stopChordNote(_ note: UInt8) {
        if !useSamples() {
            midiService.send(noteOff: note, channel: chordChannel)
        }
    }

    private func stopAllChordNotes() {
        for note in activeChordNotes {
            stopChordNote(note)
        }
        activeChordNotes.removeAll()
    }
}
