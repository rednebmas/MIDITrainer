import Foundation

/// A scheduler that reinforces incorrect sequences by re-asking them after spaced intervals.
///
/// Behavior:
/// - When a sequence is answered incorrectly, it's added to the queue with `currentClearanceDistance = clearance`.
/// - After finishing an incorrect sequence, a fresh question is always asked next.
/// - After the required number of fresh questions, the mistake is re-asked.
/// - If answered correctly on re-ask and `current >= min`, it's removed from the queue.
/// - If answered correctly but `current < min`, current increases by `clearance` for another round.
/// - If answered incorrectly on re-ask, current steps back by `clearance` (floor at base) and min grows to reflect the new failure count.
///
/// `min` is derived, not persisted state:
///     min = clearance × max(minPasses, totalFailures)
///
/// It is always recomputed from the current `clearance` and `minPasses` settings plus the card's
/// `totalFailures`. Changing either setting applies immediately to all queued cards — no migration.
/// The stored `minimumClearanceDistance` column is kept in lockstep with the derived value on every
/// write (for display consistency) but the scheduler's logic always uses the derivation.
final class SpacedMistakeScheduler: QuestionScheduler {
    private let repository: MistakeQueueRepository
    private let clearanceProvider: () -> Int
    private let minPassesProvider: () -> Int
    private var queue: [QueuedMistake] = []

    init(
        repository: MistakeQueueRepository,
        clearanceProvider: @escaping () -> Int = { 3 },
        minPassesProvider: @escaping () -> Int = { 3 }
    ) {
        self.repository = repository
        self.clearanceProvider = clearanceProvider
        self.minPassesProvider = minPassesProvider
        loadQueue()
    }

    private var clearance: Int {
        max(1, clearanceProvider())
    }

    private var minPasses: Int {
        max(1, minPassesProvider())
    }

    private func derivedMin(for mistake: QueuedMistake) -> Int {
        clearance * max(minPasses, mistake.totalFailures ?? 1)
    }

    private func tryOrLog(_ work: () throws -> Void) {
        do { try work() } catch { /* log and continue */ }
    }

    private func loadQueue() {
        do {
            queue = try repository.loadAll().map { queued in
                var adjusted = queued
                var needsUpdate = false

                if adjusted.totalFailures == nil || adjusted.totalFailures! < 1 {
                    // Legacy rows without a failure count: infer from the stored min
                    // (min was clearance × failures before failure counts were tracked).
                    let inferred = max(1, adjusted.minimumClearanceDistance / clearance)
                    adjusted.totalFailures = inferred
                    needsUpdate = true
                }

                let target = derivedMin(for: adjusted)
                if adjusted.minimumClearanceDistance != target {
                    adjusted.minimumClearanceDistance = target
                    needsUpdate = true
                }

                let clampedCurrent = max(clearance, min(adjusted.currentClearanceDistance, adjusted.minimumClearanceDistance))
                if adjusted.currentClearanceDistance != clampedCurrent {
                    adjusted.currentClearanceDistance = clampedCurrent
                    needsUpdate = true
                }

                if needsUpdate {
                    tryOrLog {
                        try repository.update(
                            id: adjusted.id,
                            minimumClearanceDistance: adjusted.minimumClearanceDistance,
                            currentClearanceDistance: adjusted.currentClearanceDistance,
                            totalFailures: adjusted.totalFailures,
                            questionsSinceQueued: adjusted.questionsSinceQueued
                        )
                    }
                }

                return adjusted
            }
        } catch {
            queue = []
        }
    }

    func reload() {
        loadQueue()
    }

    func nextQuestion(currentSettings: PracticeSettingsSnapshot) -> NextQuestion {
        // Find the first due mistake (FIFO order, already sorted by queuedAt)
        if let dueIndex = queue.firstIndex(where: { $0.isDue }) {
            let mistake = queue[dueIndex]
            // Use currentSettings so the mistake transposes to the current key
            // The seed determines the phrase (interval pattern), settings determine the key
            return .reask(seed: mistake.seed, settings: currentSettings, mistakeId: mistake.id)
        }

        // No due mistakes, return fresh
        return .fresh(seed: nil)
    }

    func recordCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, mistakeId: Int64?, sourceName: String?) {
        if let mistakeId = mistakeId {
            incrementCounters(excluding: mistakeId)
            handleReaskCompletion(mistakeId: mistakeId, hadErrors: hadErrors)
        } else {
            incrementCounters()
            handleFreshCompletion(seed: seed, settings: settings, hadErrors: hadErrors, sourceName: sourceName)
        }
    }

    private func incrementCounters(excluding excludedId: Int64? = nil) {
        tryOrLog {
            try repository.incrementAllCounters(excluding: excludedId)
            for i in queue.indices where queue[i].id != excludedId {
                queue[i].questionsSinceQueued += 1
            }
        }
    }

    private func handleFreshCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, sourceName: String?) {
        guard hadErrors else { return }
        tryOrLog {
            var mistake = try repository.insert(seed: seed, settings: settings, sourceName: sourceName, clearance: clearance)
            mistake.minimumClearanceDistance = derivedMin(for: mistake)
            try repository.update(
                id: mistake.id,
                minimumClearanceDistance: mistake.minimumClearanceDistance,
                currentClearanceDistance: mistake.currentClearanceDistance,
                totalFailures: mistake.totalFailures,
                questionsSinceQueued: mistake.questionsSinceQueued
            )
            queue.append(mistake)
        }
    }

    private func handleReaskCompletion(mistakeId: Int64, hadErrors: Bool) {
        guard let index = queue.firstIndex(where: { $0.id == mistakeId }) else { return }

        if hadErrors {
            // Failed the re-ask: bump failure count, step current back by one clearance
            // unit (floor at base clearance), and re-derive min.
            var mistake = queue[index]
            mistake.totalFailures = (mistake.totalFailures ?? 1) + 1
            mistake.currentClearanceDistance = max(clearance, mistake.currentClearanceDistance - clearance)
            mistake.minimumClearanceDistance = derivedMin(for: mistake)
            mistake.questionsSinceQueued = 0
            queue[index] = mistake

            persist(mistake)
        } else {
            // Passed the re-ask: clear if current has reached derived min, otherwise bump current.
            var mistake = queue[index]
            mistake.questionsSinceQueued = 0
            if mistake.currentClearanceDistance >= derivedMin(for: mistake) {
                queue.remove(at: index)
                tryOrLog { try repository.delete(id: mistakeId) }
            } else {
                mistake.currentClearanceDistance += clearance
                mistake.minimumClearanceDistance = derivedMin(for: mistake)
                queue[index] = mistake
                persist(mistake)
            }
        }
    }

    private func persist(_ mistake: QueuedMistake) {
        tryOrLog {
            try repository.update(
                id: mistake.id,
                minimumClearanceDistance: mistake.minimumClearanceDistance,
                currentClearanceDistance: mistake.currentClearanceDistance,
                totalFailures: mistake.totalFailures,
                questionsSinceQueued: mistake.questionsSinceQueued
            )
        }
    }

    var pendingCount: Int {
        queue.count
    }

    var questionsUntilNextReask: Int? {
        // Find the minimum remaining questions until any mistake is due
        let remaining = queue.compactMap { mistake -> Int? in
            let remaining = mistake.currentClearanceDistance - mistake.questionsSinceQueued
            return remaining > 0 ? remaining : nil
        }
        return remaining.min()
    }

    var queueSnapshot: [QueuedMistake] {
        queue.map { mistake in
            var copy = mistake
            copy.minimumClearanceDistance = derivedMin(for: mistake)
            return copy
        }
    }

    /// Resets questionsSinceQueued for a due mistake so it must wait its full clearance gap again.
    func deferMistake(id: Int64) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].questionsSinceQueued = 0
        persist(queue[index])
    }

    func clearQueue() {
        tryOrLog {
            try repository.deleteAll()
            queue.removeAll()
        }
    }
}
