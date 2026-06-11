import XCTest
@testable import MIDITrainer

final class MelodyAccuracyPredictorTests: XCTestCase {
    private func predictor(intervals: [IntervalAccuracy], start: IntervalAccuracy? = nil) -> MelodyAccuracyPredictor {
        MelodyAccuracyPredictor(stats: FirstGuessIntervalStats(intervals: intervals, start: start))
    }

    func testSmoothedAccuracyBlendsObservationWithPrior() {
        let p = predictor(intervals: [IntervalAccuracy(semitones: 2, successCount: 8, total: 10)])
        let prior = MelodyAccuracyPredictor.prior(forInterval: 2)
        XCTAssertEqual(p.accuracy(forInterval: 2), (8 + 5 * prior) / 15, accuracy: 1e-9)
    }

    func testUnseenIntervalFallsBackToPrior() {
        let p = predictor(intervals: [])
        XCTAssertEqual(p.accuracy(forInterval: 1), 0.87, accuracy: 1e-9)
        XCTAssertEqual(p.accuracy(forInterval: -7), 0.69, accuracy: 1e-9)
        XCTAssertEqual(p.accuracy(forInterval: 24), 0.45, accuracy: 1e-9, "prior floor")
    }

    func testPredictAveragesStartAndTransitions() {
        let p = predictor(
            intervals: [
                IntervalAccuracy(semitones: 2, successCount: 10, total: 10),
                IntervalAccuracy(semitones: -2, successCount: 0, total: 10),
            ],
            start: IntervalAccuracy(semitones: -9999, successCount: 5, total: 5)
        )
        let expected = (p.accuracy(forInterval: 2) + p.accuracy(forInterval: -2) + (5 + 5 * 0.85) / 10) / 3
        XCTAssertEqual(p.predict(notes: [60, 62, 60]), expected, accuracy: 1e-9)
    }

    func testHarderMelodyPredictsLowerAccuracy() {
        let p = predictor(intervals: [])
        let steps = p.predict(notes: [60, 62, 64, 65])
        let leaps = p.predict(notes: [60, 67, 60, 72])
        XCTAssertLessThan(leaps, steps)
    }
}

final class DifficultyDialTests: XCTestCase {
    func testFrozenUntilMinimumWindow() {
        let dial = DifficultyDial(target: { 0.70 })
        dial.record(noteResults: Array(repeating: true, count: 29))
        XCTAssertNil(dial.rollingAccuracy)
        XCTAssertEqual(dial.value, 0.70)
    }

    func testLowersWhenRunningHot() {
        let dial = DifficultyDial(target: { 0.70 }, seedResults: Array(repeating: true, count: 50))
        dial.record(noteResults: [true])
        XCTAssertEqual(dial.value, 0.69, accuracy: 1e-9)
    }

    func testRaisesWhenRunningCold() {
        let dial = DifficultyDial(target: { 0.70 }, seedResults: Array(repeating: false, count: 50))
        dial.record(noteResults: [false])
        XCTAssertEqual(dial.value, 0.71, accuracy: 1e-9)
    }

    func testDeadbandHolds() {
        let results = Array(repeating: true, count: 71) + Array(repeating: false, count: 29)
        let dial = DifficultyDial(target: { 0.70 }, seedResults: results)
        dial.record(noteResults: [])
        XCTAssertEqual(dial.value, 0.70, accuracy: 1e-9, "0.71 is inside the ±0.02 deadband")
    }

    func testWindowSlidesAndValueClamps() {
        let dial = DifficultyDial(target: { 0.95 }, seedResults: Array(repeating: true, count: 200))
        XCTAssertEqual(dial.rollingAccuracy, 1.0)
        for _ in 0..<200 { dial.record(noteResults: [true]) }
        XCTAssertEqual(dial.value, AdaptiveTuning.dialRange.lowerBound, accuracy: 1e-9)
    }
}

final class DifficultyTargetedSeedPickerTests: XCTestCase {
    private let settings = PracticeSettingsSnapshot(melodySourceType: .random)
    private let emptyPredictor = MelodyAccuracyPredictor(
        stats: FirstGuessIntervalStats(intervals: [], start: nil)
    )

    func testDeterministicForSameMasterSeed() {
        let picker = DifficultyTargetedSeedPicker()
        let a = picker.pickSeed(settings: settings, dial: 0.7, predictor: emptyPredictor, masterSeed: 42)
        let b = picker.pickSeed(settings: settings, dial: 0.7, predictor: emptyPredictor, masterSeed: 42)
        XCTAssertEqual(a, b)
    }

    func testChosenSeedIsClosestCandidateAndReproducible() {
        let picker = DifficultyTargetedSeedPicker()
        let generator = SequenceGenerator()
        let dial = 0.65
        let chosen = picker.pickSeed(settings: settings, dial: dial, predictor: emptyPredictor, masterSeed: 7)

        var rng = SeededGenerator(seed: 7)
        let distances = (0..<AdaptiveTuning.candidateCount).map { _ -> (seed: UInt64, distance: Double) in
            let seed = rng.next()
            let notes = generator.generate(settings: settings, seed: seed).notes.map(\.midiNoteNumber)
            return (seed, abs(emptyPredictor.predict(notes: notes) - dial))
        }
        let best = distances.min { $0.distance < $1.distance }!
        XCTAssertEqual(chosen, best.seed)

        let first = generator.generate(settings: settings, seed: chosen).notes
        let second = generator.generate(settings: settings, seed: chosen).notes
        XCTAssertEqual(first, second, "chosen seed must regenerate the identical melody")
    }
}
