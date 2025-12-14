import Foundation

/// A scheduler that prioritizes historically weak sequences while maintaining short-term reinforcement.
///
/// Behavior:
/// - First checks if the composed SpacedMistakeScheduler has a due re-ask (immediate reinforcement)
/// - If no immediate re-ask, selects from historical weaknesses using weighted random selection
/// - Weight is based on first-attempt failure count (more failures = higher weight)
/// - Falls back to fresh questions if no weaknesses exist
final class WeaknessFocusedScheduler: QuestionScheduler {
    private let spacedScheduler: SpacedMistakeScheduler
    private let statsRepository: StatsRepository
    private let matchExactSettings: () -> Bool

    init(
        spacedScheduler: SpacedMistakeScheduler,
        statsRepository: StatsRepository,
        matchExactSettings: @escaping () -> Bool = { false }
    ) {
        self.spacedScheduler = spacedScheduler
        self.statsRepository = statsRepository
        self.matchExactSettings = matchExactSettings
    }

    func nextQuestion(currentSettings: PracticeSettingsSnapshot) -> NextQuestion {
        // 1. First check if spaced scheduler has a due re-ask (short-term reinforcement takes priority)
        let spacedResult = spacedScheduler.nextQuestion(currentSettings: currentSettings)
        if case .reask = spacedResult {
            return spacedResult
        }

        // 2. Otherwise, select from historical weaknesses
        if let weakness = selectWeightedWeakness(for: currentSettings) {
            // Return as a reask but without a mistakeId (it's from historical data, not the queue)
            return .reask(seed: weakness.seed, settings: currentSettings, mistakeId: -1)
        }

        // 3. Fallback to fresh question
        return .fresh
    }

    func recordCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, mistakeId: Int64?) {
        // Delegate to spaced scheduler for immediate queue management
        // Historical weakness data comes from existing note_attempt table (no extra recording needed)

        // For weakness-selected questions (mistakeId == -1), treat as fresh for the spaced scheduler
        let actualMistakeId = mistakeId == -1 ? nil : mistakeId
        spacedScheduler.recordCompletion(seed: seed, settings: settings, hadErrors: hadErrors, mistakeId: actualMistakeId)
    }

    private func selectWeightedWeakness(for settings: PracticeSettingsSnapshot) -> WeaknessEntry? {
        // Get top weaknesses with at least 1 first-attempt failure
        guard let candidates = try? statsRepository.topWeaknesses(
            for: settings,
            limit: 20,
            matchExactSettings: matchExactSettings()
        ), !candidates.isEmpty else {
            return nil
        }

        // Calculate weights (simply use firstAttemptFailures count)
        let weights = candidates.map { $0.weight }

        // Weighted random selection
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return nil }

        let random = Double.random(in: 0..<totalWeight)

        var cumulative = 0.0
        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if random < cumulative {
                return candidates[index]
            }
        }

        return candidates.last
    }

    var pendingCount: Int {
        spacedScheduler.pendingCount
    }

    var questionsUntilNextReask: Int? {
        spacedScheduler.questionsUntilNextReask
    }

    var queueSnapshot: [QueuedMistake] {
        spacedScheduler.queueSnapshot
    }

    func clearQueue() {
        spacedScheduler.clearQueue()
    }
}
