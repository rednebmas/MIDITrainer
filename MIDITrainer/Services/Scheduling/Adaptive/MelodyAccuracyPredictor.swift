import Foundation

/// Predicts first-guess accuracy for a melody from per-interval history.
///
/// Observed rates are smoothed toward a leap-size prior so unseen or rarely
/// seen intervals get sensible estimates (unseen big leaps assumed hard,
/// unseen steps assumed easy).
struct MelodyAccuracyPredictor {
    private let byInterval: [Int: IntervalAccuracy]
    private let start: IntervalAccuracy?

    init(stats: FirstGuessIntervalStats) {
        byInterval = Dictionary(
            stats.intervals.map { ($0.semitones, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        start = stats.start
    }

    func accuracy(forInterval semitones: Int) -> Double {
        smoothed(byInterval[semitones], prior: Self.prior(forInterval: semitones))
    }

    /// Mean predicted accuracy over the melody's first note and transitions.
    func predict(notes: [UInt8]) -> Double {
        guard !notes.isEmpty else { return 1 }
        var accuracies = [smoothed(start, prior: AdaptiveTuning.startPrior)]
        for (previous, current) in zip(notes, notes.dropFirst()) {
            accuracies.append(accuracy(forInterval: Int(current) - Int(previous)))
        }
        return accuracies.reduce(0, +) / Double(accuracies.count)
    }

    private func smoothed(_ observed: IntervalAccuracy?, prior: Double) -> Double {
        let weight = AdaptiveTuning.smoothingWeight
        let successes = Double(observed?.successCount ?? 0)
        let total = Double(observed?.total ?? 0)
        return (successes + weight * prior) / (total + weight)
    }

    static func prior(forInterval semitones: Int) -> Double {
        let raw = 0.9 - AdaptiveTuning.priorSlopePerSemitone * Double(abs(semitones))
        return raw.clamped(to: AdaptiveTuning.priorRange)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
