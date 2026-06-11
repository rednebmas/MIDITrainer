import Combine
import XCTest
@testable import MIDITrainer

/// Drives the real PracticeEngine + SchedulingCoordinator through a fragment
/// drill end-to-end: a due fragment is served as a 2-note question, played
/// back, answered on the (mock) keyboard, persisted, and scored.
final class AdaptiveFragmentIntegrationTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    func testDueFragmentPlaysAndRecordsEndToEnd() throws {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).sqlite"
        let db = try Database(path: path)
        let fragmentRepo = FragmentQueueRepository(db: db)
        let statsRepo = StatsRepository(db: db)
        let settings = PracticeSettingsSnapshot()

        // Queue a due ↑P4 fragment: v/oct4 → i/oct5 (G4 → C5 in C major)
        let fragment = ExtractedFragment(
            fromDegree: .v, fromOctave: 4, toDegree: .i, toOctave: 5, intervalSemitones: 5
        )
        let row = try fragmentRepo.insert(fragment, parentMistakeId: nil, sourceName: "Dark Horse")
        try fragmentRepo.update(
            id: row.id, consecutiveCorrect: 0,
            questionsSinceAsked: AdaptiveTuning.fragmentSpacing, totalFailures: 1
        )

        let coordinator = SchedulingCoordinator(
            initialMode: .adaptive,
            repository: MistakeQueueRepository(db: db),
            fragmentRepository: fragmentRepo,
            statsRepository: statsRepo,
            onModeChange: { _ in }
        )
        let midiService = MockMIDIService()
        let engine = PracticeEngine(
            midiService: midiService,
            sequenceGenerator: SequenceGenerator(),
            playbackScheduler: PlaybackScheduler(midiService: midiService),
            scoringService: ScoringService(),
            settingsRepository: SettingsSnapshotRepository(db: db),
            sessionRepository: SessionRepository(db: db),
            sequenceRepository: SequenceRepository(db: db),
            attemptRepository: AttemptRepository(db: db),
            statsRepository: statsRepo,
            replayHotkeyNote: { nil },
            currentSettingsProvider: { settings },
            schedulingCoordinator: coordinator
        )

        let awaitingInput = expectation(description: "fragment playback finished")
        let completed = expectation(description: "fragment completed")
        var playedSequence: MelodySequence?
        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { state in
                switch state {
                case .active(let sequence, false):
                    playedSequence = sequence
                    awaitingInput.fulfill()
                case .completed:
                    completed.fulfill()
                default:
                    break
                }
            }
            .store(in: &cancellables)

        engine.playQuestion(settings: settings)
        wait(for: [awaitingInput], timeout: 10)

        let sequence = try XCTUnwrap(playedSequence)
        XCTAssertEqual(sequence.notes.map(\.midiNoteNumber), [67, 72])
        XCTAssertEqual(sequence.sourceId, "fragment")
        XCTAssertEqual(sequence.sourceName, "↑P4 drill from Dark Horse")

        for note in [UInt8(67), UInt8(72)] {
            midiService.injectNoteEvent(.noteOn(noteNumber: note, velocity: 100))
            midiService.injectNoteEvent(.noteOff(noteNumber: note))
        }
        wait(for: [completed], timeout: 10)

        let after = try fragmentRepo.loadAll()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].consecutiveCorrect, 1, "clean first-guess pass advances the streak")
        XCTAssertEqual(after[0].questionsSinceAsked, 0)

        let history = try statsRepo.sequenceHistory(for: settings, limit: 5)
        let drillEntry = try XCTUnwrap(history.first { $0.sourceName?.contains("drill") == true })
        XCTAssertEqual(drillEntry.midiNotes, [67, 72])
        XCTAssertTrue(drillEntry.wasCorrectFirstTry)
    }
}
