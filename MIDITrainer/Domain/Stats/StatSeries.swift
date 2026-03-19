import Foundation

struct StatBucket: Equatable {
    let label: String
    let rate: Double
    let total: Int
}

struct ConfusionBucket: Equatable {
    let expectedLabel: String
    let guessedLabel: String
    let count: Int
}

struct RecoveryStats {
    let averageAttempts: Double
    let totalRecoveries: Int
}

struct TrendPoint: Identifiable {
    let id: Int
    let value: Double
}
