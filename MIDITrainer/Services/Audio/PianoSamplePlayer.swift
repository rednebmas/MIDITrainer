import AVFoundation
import Foundation

/// Plays piano samples for given MIDI note numbers
final class PianoSamplePlayer {
    private let audioEngine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var sampleBuffers: [UInt8: AVAudioPCMBuffer] = [:]
    private var activePlayers: [AVAudioPlayerNode] = []
    private let playerPool: [AVAudioPlayerNode]
    private var nextPlayerIndex = 0
    private let poolSize = 16  // Support up to 16 simultaneous notes

    private let noteNames = ["C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B"]

    init() {
        // Create player pool
        var players: [AVAudioPlayerNode] = []
        for _ in 0..<poolSize {
            let player = AVAudioPlayerNode()
            players.append(player)
        }
        self.playerPool = players

        setupAudioEngine()
        loadSamples()
    }

    private func setupAudioEngine() {
        // Attach mixer
        audioEngine.attach(mixer)
        audioEngine.connect(mixer, to: audioEngine.mainMixerNode, format: nil)

        // Attach all players to the mixer
        for player in playerPool {
            audioEngine.attach(player)
            audioEngine.connect(player, to: mixer, format: nil)
        }

        // Configure audio session for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }

        // Start the engine
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    private func loadSamples() {
        // Load samples for MIDI notes we have (approximately E2 to C6)
        // MIDI note 40 = E2, 84 = C6
        for midiNote: UInt8 in 36...96 {
            if let buffer = loadSample(for: midiNote) {
                sampleBuffers[midiNote] = buffer
            }
        }
        print("Loaded \(sampleBuffers.count) piano samples")
    }

    private func loadSample(for midiNote: UInt8) -> AVAudioPCMBuffer? {
        let octave = Int(midiNote) / 12 - 1
        let noteIndex = Int(midiNote) % 12
        let noteName = noteNames[noteIndex]
        let filename = "Piano.ff.\(noteName)\(octave)"

        guard let url = Bundle.main.url(forResource: filename, withExtension: "mp3") else {
            return nil
        }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let frameCount = AVAudioFrameCount(audioFile.length)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return nil
            }

            try audioFile.read(into: buffer)
            return buffer
        } catch {
            print("Failed to load sample \(filename): \(error)")
            return nil
        }
    }

    /// Play a note by MIDI number
    func play(midiNote: UInt8, velocity: UInt8 = 100) {
        guard let buffer = sampleBuffers[midiNote] else {
            // Try to find nearest available sample
            if let nearestBuffer = findNearestSample(for: midiNote) {
                playBuffer(nearestBuffer, velocity: velocity)
            }
            return
        }
        playBuffer(buffer, velocity: velocity)
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer, velocity: UInt8) {
        // Get next player from pool (round-robin)
        let player = playerPool[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % poolSize

        // Stop if already playing
        if player.isPlaying {
            player.stop()
        }

        // Calculate volume based on velocity (0-127)
        let volume = Float(velocity) / 127.0

        // Schedule and play
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    private func findNearestSample(for midiNote: UInt8) -> AVAudioPCMBuffer? {
        // Search for nearest available sample (within an octave)
        for offset in 0...12 {
            if let buffer = sampleBuffers[midiNote + UInt8(offset)] {
                return buffer
            }
            if midiNote >= UInt8(offset), let buffer = sampleBuffers[midiNote - UInt8(offset)] {
                return buffer
            }
        }
        return nil
    }

    /// Stop all currently playing notes
    func stopAll() {
        for player in playerPool {
            player.stop()
        }
    }

    /// Ensure the audio engine is running
    func ensureRunning() {
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("Failed to restart audio engine: \(error)")
            }
        }
    }
}
