import Combine
import XCTest
@testable import MIDITrainer

// MARK: - Mock Services

final class MockMIDIService: MIDIService {
    var availableInputsPublisher: AnyPublisher<[MIDIEndpoint], Never> {
        Just([]).eraseToAnyPublisher()
    }
    var connectedInputsPublisher: AnyPublisher<[MIDIEndpoint], Never> {
        Just([]).eraseToAnyPublisher()
    }
    var availableOutputsPublisher: AnyPublisher<[MIDIEndpoint], Never> {
        Just([]).eraseToAnyPublisher()
    }
    var selectedOutputPublisher: AnyPublisher<MIDIEndpoint?, Never> {
        Just(nil).eraseToAnyPublisher()
    }
    
    private let noteSubject = PassthroughSubject<MIDINoteEvent, Never>()
    var noteEvents: AnyPublisher<MIDINoteEvent, Never> {
        noteSubject.eraseToAnyPublisher()
    }
    
    func start() {}
    func stop() {}
    func refreshEndpoints() {}
    func connectInput(_ endpoint: MIDIEndpoint) {}
    func disconnectInput(_ endpoint: MIDIEndpoint) {}
    func selectOutput(_ endpoint: MIDIEndpoint?) {}
    func send(noteOn noteNumber: UInt8, velocity: UInt8, channel: Int) {}
    func send(noteOff noteNumber: UInt8, channel: Int) {}
    func injectNoteEvent(_ event: MIDINoteEvent) {
        noteSubject.send(event)
    }

    // Test helper to simulate note input
    func simulateNoteOn(_ noteNumber: UInt8, velocity: UInt8 = 100) {
        noteSubject.send(.noteOn(noteNumber: noteNumber, velocity: velocity))
    }
}

final class MockPlaybackScheduler {
    var playCallCount = 0
    var lastPlayedSequence: MelodySequence?
    private var completionHandler: (() -> Void)?
    
    func play(sequence: MelodySequence, velocity: UInt8 = 96, completion: (() -> Void)? = nil) {
        playCallCount += 1
        lastPlayedSequence = sequence
        completionHandler = completion
    }
    
    // Test helper to simulate playback completion
    func completePlayback() {
        completionHandler?()
        completionHandler = nil
    }
}

final class MockFeedbackService {
    var successPlayedCount = 0
    
    func playSequenceSuccess(for key: Key, settings: FeedbackSettings) {
        successPlayedCount += 1
    }
}

// MARK: - Testable PracticeEngine

/// A testable version of PracticeEngine that exposes internal state for testing
final class TestablePracticeEngine {
    enum State: Equatable {
        case idle
        case playing(MelodySequence)
        case awaitingInput(sequence: MelodySequence, expectedIndex: Int)
        case completed(MelodySequence)
    }
    
    private(set) var state: State = .idle
    
    private let midiService: MockMIDIService
    private let playbackScheduler: MockPlaybackScheduler
    private let feedbackService: MockFeedbackService
    private let sequenceGenerator: SequenceGenerator
    private let scoringService: ScoringService
    private var cancellables: Set<AnyCancellable> = []
    
    private var currentInputIndex: Int = 0
    private(set) var madeErrorInCurrentSequence: Bool = false
    private var playbackFinished: Bool = false
    private var lastCorrectExpected: UInt8?
    private var lastCorrectGuessed: UInt8?
    private var currentSettings: PracticeSettingsSnapshot?
    
    /// Counts how many times auto-advance triggered a new question
    var autoAdvanceCount = 0
    /// Counts how many times auto-replay was triggered
    var autoReplayCount = 0
    
    init(
        midiService: MockMIDIService = MockMIDIService(),
        playbackScheduler: MockPlaybackScheduler = MockPlaybackScheduler(),
        feedbackService: MockFeedbackService = MockFeedbackService()
    ) {
        self.midiService = midiService
        self.playbackScheduler = playbackScheduler
        self.feedbackService = feedbackService
        self.sequenceGenerator = SequenceGenerator()
        self.scoringService = ScoringService()
        
        bindMIDI()
    }
    
    func playQuestion(settings: PracticeSettingsSnapshot, seed: UInt64? = nil) {
        currentSettings = settings
        let sequence = sequenceGenerator.generate(settings: settings, seed: seed)
        
        currentInputIndex = 0
        madeErrorInCurrentSequence = false
        playbackFinished = false
        lastCorrectExpected = nil
        lastCorrectGuessed = nil
        
        state = .playing(sequence)
        
        playbackScheduler.play(sequence: sequence) { [weak self] in
            self?.onPlaybackComplete()
        }
    }
    
    private func onPlaybackComplete() {
        playbackFinished = true
        
        if case .playing(let seq) = state, currentInputIndex >= seq.notes.count {
            handleSequenceCompleted(sequence: seq)
        } else if case .playing(let seq) = state {
            state = .awaitingInput(sequence: seq, expectedIndex: currentInputIndex)
        }
    }
    
    /// Simulate playback completion (for testing)
    func simulatePlaybackComplete() {
        playbackScheduler.completePlayback()
    }
    
    private func bindMIDI() {
        midiService.noteEvents
            .sink { [weak self] event in
                guard case let .noteOn(noteNumber, _) = event else { return }
                self?.handle(noteOn: noteNumber)
            }
            .store(in: &cancellables)
    }
    
    private func handle(noteOn noteNumber: UInt8) {
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
        
        if isCorrect {
            lastCorrectExpected = expectedNote.midiNoteNumber
            lastCorrectGuessed = noteNumber
            let nextIndex = expectedIndex + 1
            currentInputIndex = nextIndex
            
            if nextIndex >= sequence.notes.count {
                if playbackFinished {
                    handleSequenceCompleted(sequence: sequence)
                }
            } else {
                if case .awaitingInput = state {
                    state = .awaitingInput(sequence: sequence, expectedIndex: nextIndex)
                }
            }
        } else {
            madeErrorInCurrentSequence = true
        }
    }
    
    private func handleSequenceCompleted(sequence: MelodySequence) {
        state = .completed(sequence)
        
        if madeErrorInCurrentSequence {
            autoReplayCount += 1
            // In real engine, this would trigger replay after delay
            // For testing, we just track the count
        } else {
            feedbackService.successPlayedCount += 1
            autoAdvanceCount += 1
            // In real engine, this would trigger next question after delay
        }
    }
    
    // MARK: - Test Helpers
    
    func simulateNoteOn(_ noteNumber: UInt8) {
        midiService.simulateNoteOn(noteNumber)
    }
    
    var currentSequence: MelodySequence? {
        switch state {
        case .playing(let seq), .awaitingInput(let seq, _), .completed(let seq):
            return seq
        case .idle:
            return nil
        }
    }
}

// MARK: - Tests

final class PracticeEngineTests: XCTestCase {
    
    private func makeSettings() -> PracticeSettingsSnapshot {
        PracticeSettingsSnapshot(
            key: Key(root: .c),
            scaleType: .major,
            excludedDegrees: [],
            allowedOctaves: [4],
            melodyLength: 4,
            bpm: 120
        )
    }
    
    // MARK: - Test: Input during playback
    
    func testInputAcceptedDuringPlayback() {
        let engine = TestablePracticeEngine()
        let settings = makeSettings()
        
        // Start playing
        engine.playQuestion(settings: settings, seed: 42)
        
        // Verify we're in playing state
        guard case .playing(let sequence) = engine.state else {
            XCTFail("Expected playing state")
            return
        }
        
        // Play the first note while still in "playing" state (before playback completes)
        let firstNote = sequence.notes[0].midiNoteNumber
        engine.simulateNoteOn(firstNote)
        
        // State should still be playing (playback hasn't finished)
        // but the internal index should have advanced
        if case .playing = engine.state {
            // This is expected - still playing but input was accepted
        } else {
            XCTFail("Expected to still be in playing state")
        }
        
        // Now complete playback
        engine.simulatePlaybackComplete()
        
        // Should be awaiting input at index 1 (since we already played note 0)
        if case .awaitingInput(_, let idx) = engine.state {
            XCTAssertEqual(idx, 1, "Should be waiting for second note since first was played during playback")
        } else {
            XCTFail("Expected awaitingInput state after playback completes")
        }
    }
    
    // MARK: - Test: Complete sequence during playback
    
    func testCompleteSequenceDuringPlayback() {
        let engine = TestablePracticeEngine()
        let settings = makeSettings()
        
        engine.playQuestion(settings: settings, seed: 42)
        
        guard case .playing(let sequence) = engine.state else {
            XCTFail("Expected playing state")
            return
        }
        
        // Play all notes correctly while still in playing state
        for note in sequence.notes {
            engine.simulateNoteOn(note.midiNoteNumber)
        }
        
        // Still in playing state because playback hasn't finished
        if case .playing = engine.state {
            // Expected
        } else {
            XCTFail("Should still be playing until playback completes")
        }
        
        // Complete playback - should trigger completion
        engine.simulatePlaybackComplete()
        
        if case .completed = engine.state {
            XCTAssertEqual(engine.autoAdvanceCount, 1, "Should trigger auto-advance on perfect completion")
            XCTAssertFalse(engine.madeErrorInCurrentSequence)
        } else {
            XCTFail("Expected completed state")
        }
    }
    
    // MARK: - Test: Auto-advance on success (no errors)
    
    func testAutoAdvanceOnPerfectSequence() {
        let engine = TestablePracticeEngine()
        let settings = makeSettings()
        
        engine.playQuestion(settings: settings, seed: 42)
        
        guard case .playing(let sequence) = engine.state else {
            XCTFail("Expected playing state")
            return
        }
        
        // Complete playback first
        engine.simulatePlaybackComplete()
        
        // Now play all notes correctly
        for note in sequence.notes {
            engine.simulateNoteOn(note.midiNoteNumber)
        }
        
        // Should be completed with auto-advance triggered
        if case .completed = engine.state {
            XCTAssertEqual(engine.autoAdvanceCount, 1)
            XCTAssertEqual(engine.autoReplayCount, 0)
        } else {
            XCTFail("Expected completed state")
        }
    }
    
    // MARK: - Test: Auto-replay on error
    
    func testAutoReplayOnError() {
        let engine = TestablePracticeEngine()
        let settings = makeSettings()
        
        engine.playQuestion(settings: settings, seed: 42)
        
        guard case .playing(let sequence) = engine.state else {
            XCTFail("Expected playing state")
            return
        }
        
        // Complete playback
        engine.simulatePlaybackComplete()
        
        // Make a mistake on the first note
        let wrongNote = sequence.notes[0].midiNoteNumber + 1 // Wrong note
        engine.simulateNoteOn(wrongNote)
        
        XCTAssertTrue(engine.madeErrorInCurrentSequence, "Error should be recorded")
        
        // Now play all notes correctly
        for note in sequence.notes {
            engine.simulateNoteOn(note.midiNoteNumber)
        }
        
        // Should be completed with auto-replay triggered (due to earlier error)
        if case .completed = engine.state {
            XCTAssertEqual(engine.autoReplayCount, 1, "Should trigger replay due to error")
            XCTAssertEqual(engine.autoAdvanceCount, 0, "Should NOT auto-advance when errors occurred")
        } else {
            XCTFail("Expected completed state")
        }
    }
    
    // MARK: - Test: State transitions
    
    func testStateTransitions() {
        let engine = TestablePracticeEngine()
        let settings = makeSettings()
        
        // Initial state
        if case .idle = engine.state {
            // Expected
        } else {
            XCTFail("Initial state should be idle")
        }
        
        // After playQuestion
        engine.playQuestion(settings: settings, seed: 42)
        if case .playing = engine.state {
            // Expected
        } else {
            XCTFail("Should be playing after playQuestion")
        }
        
        // After playback completes
        engine.simulatePlaybackComplete()
        if case .awaitingInput(_, let idx) = engine.state {
            XCTAssertEqual(idx, 0, "Should await first note")
        } else {
            XCTFail("Should be awaiting input after playback")
        }
    }
    
    // MARK: - Test: Wrong notes don't advance index
    
    func testWrongNoteDoesNotAdvance() {
        let engine = TestablePracticeEngine()
        let settings = makeSettings()
        
        engine.playQuestion(settings: settings, seed: 42)
        engine.simulatePlaybackComplete()
        
        guard case .awaitingInput(let sequence, _) = engine.state else {
            XCTFail("Expected awaiting input state")
            return
        }
        
        // Play wrong note
        let wrongNote = sequence.notes[0].midiNoteNumber + 2
        engine.simulateNoteOn(wrongNote)
        
        // Should still be waiting for first note
        if case .awaitingInput(_, let idx) = engine.state {
            XCTAssertEqual(idx, 0, "Index should not advance on wrong note")
        } else {
            XCTFail("Should still be awaiting input")
        }
        
        XCTAssertTrue(engine.madeErrorInCurrentSequence)
    }
}
