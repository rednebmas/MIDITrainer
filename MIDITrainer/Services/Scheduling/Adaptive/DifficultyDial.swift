import Foundation

/// Thermostat that keeps measured first-guess accuracy near the user's target
/// by steering the predicted-accuracy level requested from the generator.
///
/// When the user runs hot (above target), the dial lowers — harder melodies.
/// When they run cold, it raises — easier melodies.
final class DifficultyDial {
    private let target: () -> Double
    private var window: [Bool]
    private(set) var value: Double

    init(target: @escaping () -> Double, seedResults: [Bool] = []) {
        self.target = target
        self.window = Array(seedResults.suffix(AdaptiveTuning.rollingWindowSize))
        self.value = target().clamped(to: AdaptiveTuning.dialRange)
    }

    var rollingAccuracy: Double? {
        guard window.count >= AdaptiveTuning.minWindowForAdjustment else { return nil }
        return Double(window.lazy.filter { $0 }.count) / Double(window.count)
    }

    /// Feed one completed question's first-guess note results, then adjust.
    func record(noteResults: [Bool]) {
        window.append(contentsOf: noteResults)
        if window.count > AdaptiveTuning.rollingWindowSize {
            window.removeFirst(window.count - AdaptiveTuning.rollingWindowSize)
        }
        adjust()
    }

    private func adjust() {
        guard let rolling = rollingAccuracy else { return }
        let goal = target()
        if rolling > goal + AdaptiveTuning.deadband {
            value = (value - AdaptiveTuning.dialStep).clamped(to: AdaptiveTuning.dialRange)
        } else if rolling < goal - AdaptiveTuning.deadband {
            value = (value + AdaptiveTuning.dialStep).clamped(to: AdaptiveTuning.dialRange)
        }
    }
}
