import Foundation

/// Central knobs for the adaptive practice mode, grouped for easy revision
/// after real-world use.
enum AdaptiveTuning {
    // Difficulty dial (thermostat)
    static let dialStep = 0.01
    static let deadband = 0.02
    static let dialRange = 0.50...0.98
    static let rollingWindowSize = 100
    static let minWindowForAdjustment = 30

    // Fresh-question candidate sampling
    static let candidateCount = 12

    // Fragment drills
    static let clearStreak = 3
    static let fragmentSpacing = 2

    // Accuracy predictor smoothing
    static let smoothingWeight = 5.0
    static let priorSlopePerSemitone = 0.03
    static let priorRange = 0.45...0.9
    static let startPrior = 0.85

    // Stats recency window
    static let statsRecencyDays = 90.0
    static let minRecentAttempts = 200
}
