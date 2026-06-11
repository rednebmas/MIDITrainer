import Foundation

/// A scheduler that reinforces incorrect sequences by re-asking them after spaced intervals.
///
/// Behavior:
/// - When a sequence is answered incorrectly, it's added to the queue with `currentClearance = clearance`.
/// - After finishing an incorrect sequence, a fresh question is always asked next.
/// - After the required number of fresh questions, the mistake is re-asked.
/// - If answered correctly on re-ask and `currentClearance >= requiredClearance`, it's cleared.
/// - If answered correctly but below the requirement, `currentClearance` grows by `clearance` for another round.
/// - If answered incorrectly on re-ask, `currentClearance` steps back by `clearance` (floor at base)
///   and the failure count grows — which inflates the requirement.
///
/// The requirement is derived, never stored:
///     requiredClearance = clearance × max(minPasses, totalFailures)
///
/// Changing the clearance or minPasses settings applies immediately to all queued cards.
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

    private func required(for mistake: QueuedMistake) -> Int {
        mistake.requiredClearance(clearance: clearance, minPasses: minPasses)
    }

    private func tryOrLog(_ work: () throws -> Void) {
        do { try work() } catch { /* log and continue */ }
    }

    private func loadQueue() {
        do {
            queue = try repository.loadAll().map { loaded in
                let adjusted = loaded.normalized(clearance: clearance, minPasses: minPasses)
                if adjusted != loaded {
                    persist(adjusted)
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
                queue[i].questionsWaited += 1
            }
        }
    }

    private func handleFreshCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, sourceName: String?) {
        guard hadErrors else { return }
        tryOrLog {
            let mistake = try repository.insert(seed: seed, settings: settings, sourceName: sourceName, clearance: clearance)
            queue.append(mistake)
        }
    }

    private func handleReaskCompletion(mistakeId: Int64, hadErrors: Bool) {
        guard let index = queue.firstIndex(where: { $0.id == mistakeId }) else { return }

        if hadErrors {
            // Failed the re-ask: bump failure count and step current back by one
            // clearance unit (floor at base clearance).
            var mistake = queue[index]
            mistake.totalFailures = (mistake.totalFailures ?? 1) + 1
            mistake.currentClearance = max(clearance, mistake.currentClearance - clearance)
            mistake.questionsWaited = 0
            queue[index] = mistake

            persist(mistake)
        } else {
            // Passed the re-ask: clear if current has reached the requirement, otherwise bump current.
            var mistake = queue[index]
            mistake.questionsWaited = 0
            if mistake.currentClearance >= required(for: mistake) {
                queue.remove(at: index)
                tryOrLog { try repository.markCleared(id: mistakeId) }
            } else {
                mistake.currentClearance += clearance
                queue[index] = mistake
                persist(mistake)
            }
        }
    }

    private func persist(_ mistake: QueuedMistake) {
        tryOrLog {
            try repository.update(
                id: mistake.id,
                currentClearance: mistake.currentClearance,
                totalFailures: mistake.totalFailures,
                questionsWaited: mistake.questionsWaited
            )
        }
    }

    var pendingCount: Int {
        queue.count
    }

    var questionsUntilNextReask: Int? {
        // Find the minimum remaining questions until any mistake is due
        let remaining = queue.compactMap { mistake -> Int? in
            let remaining = mistake.currentClearance - mistake.questionsWaited
            return remaining > 0 ? remaining : nil
        }
        return remaining.min()
    }

    var queueSnapshot: [QueuedMistake] {
        queue
    }

    /// Resets questionsWaited for a due mistake so it must wait its full clearance gap again.
    func deferMistake(id: Int64) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].questionsWaited = 0
        persist(queue[index])
    }

    func clearQueue() {
        tryOrLog {
            try repository.deleteAll()
            queue.removeAll()
        }
    }
}
