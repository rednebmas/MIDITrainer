import Foundation

/// A scheduler that reinforces incorrect sequences by re-asking them after spaced intervals.
///
/// Behavior:
/// - When a sequence is answered incorrectly, it's added to the queue with clearance distance 3.
/// - After finishing an incorrect sequence, a fresh question is always asked next.
/// - After the required number of fresh questions, the mistake is re-asked.
/// - If answered correctly on re-ask and current > min, it's removed from the queue.
/// - If answered correctly but current <= min, current increases by clearance for another round.
/// - If answered incorrectly on re-ask, min increases by clearance and current resets to clearance.
///
/// Two distances are tracked:
/// - minimumClearanceDistance: the eventual spacing needed to clear the item (increases by clearance on each failed re-ask).
/// - currentClearanceDistance: the spacing before the next re-ask (increases by clearance on both failure and success).
final class SpacedMistakeScheduler: QuestionScheduler {
    private let repository: MistakeQueueRepository
    private let clearanceProvider: () -> Int
    private var queue: [QueuedMistake] = []

    init(repository: MistakeQueueRepository, clearanceProvider: @escaping () -> Int = { 3 }) {
        self.repository = repository
        self.clearanceProvider = clearanceProvider
        loadQueue()
    }

    private var clearance: Int {
        max(1, clearanceProvider())
    }
    
    private func loadQueue() {
        do {
            queue = try repository.loadAll().map { queued in
                var adjusted = queued
                var needsUpdate = false

                if adjusted.minimumClearanceDistance < clearance {
                    adjusted.minimumClearanceDistance = clearance
                    needsUpdate = true
                }
                let clampedCurrent = max(clearance, min(adjusted.currentClearanceDistance, adjusted.minimumClearanceDistance))
                if adjusted.currentClearanceDistance != clampedCurrent {
                    adjusted.currentClearanceDistance = clampedCurrent
                    needsUpdate = true
                }

                if needsUpdate {
                    do {
                        try repository.update(
                            id: adjusted.id,
                            minimumClearanceDistance: adjusted.minimumClearanceDistance,
                            currentClearanceDistance: adjusted.currentClearanceDistance,
                            questionsSinceQueued: adjusted.questionsSinceQueued
                        )
                    } catch {
                        // Log error but continue with adjusted in-memory state
                    }
                }

                return adjusted
            }
        } catch {
            queue = []
        }
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
        return .fresh
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
        do {
            try repository.incrementAllCounters(excluding: excludedId)
            for i in queue.indices where queue[i].id != excludedId {
                queue[i].questionsSinceQueued += 1
            }
        } catch {
            // Log error but continue
        }
    }
    
    private func handleFreshCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, sourceName: String?) {
        // If the fresh question had errors, add it to the queue
        if hadErrors {
            do {
                let mistake = try repository.insert(seed: seed, settings: settings, sourceName: sourceName, clearance: clearance)
                queue.append(mistake)
            } catch {
                // Log error but continue
            }
        }
    }
    
    private func handleReaskCompletion(mistakeId: Int64, hadErrors: Bool) {
        guard let index = queue.firstIndex(where: { $0.id == mistakeId }) else { return }

        if hadErrors {
            // Failed the re-ask: bump minimum (harder to clear) but reset current to base (re-ask soon)
            var mistake = queue[index]
            mistake.minimumClearanceDistance += clearance
            mistake.currentClearanceDistance = clearance
            mistake.questionsSinceQueued = 0
            queue[index] = mistake
            
            do {
                try repository.update(
                    id: mistakeId,
                    minimumClearanceDistance: mistake.minimumClearanceDistance,
                    currentClearanceDistance: mistake.currentClearanceDistance,
                    questionsSinceQueued: mistake.questionsSinceQueued
                )
            } catch {
                // Log error but continue
            }
        } else {
            // Passed the re-ask: clear if current exceeds min, otherwise bump current so next pass clears.
            var mistake = queue[index]
            mistake.questionsSinceQueued = 0
            if mistake.currentClearanceDistance > mistake.minimumClearanceDistance {
                queue.remove(at: index)
                do {
                    try repository.delete(id: mistakeId)
                } catch {
                    // Log error but continue
                }
            } else {
                mistake.currentClearanceDistance += clearance
                queue[index] = mistake
                do {
                    try repository.update(
                        id: mistakeId,
                        minimumClearanceDistance: mistake.minimumClearanceDistance,
                        currentClearanceDistance: mistake.currentClearanceDistance,
                        questionsSinceQueued: mistake.questionsSinceQueued
                    )
                } catch {
                    // Log error but continue
                }
            }
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
        queue
    }
    
    func clearQueue() {
        do {
            try repository.deleteAll()
            queue.removeAll()
        } catch {
            // Log error but continue
        }
    }
}
