import Foundation

/// A scheduler that reinforces incorrect sequences by re-asking them after spaced intervals.
/// 
/// Behavior:
/// - When a sequence is answered incorrectly, it's added to the queue with clearance distance 1.
/// - After finishing an incorrect sequence, a fresh question is always asked next.
/// - After the required number of fresh questions, the mistake is re-asked.
/// - If answered correctly on re-ask, it's removed from the queue.
/// - If answered incorrectly on re-ask, clearance distance is multiplied by 3 and it's requeued.
/// 
/// Two distances are tracked:
/// - minimumClearanceDistance: how far apart a correct re-ask must eventually be to clear the item (multiplies by 3 on each failed re-ask).
/// - currentClearanceDistance: the immediate spacing required before the next re-ask (resets to 1 on failure, set up to the minimum on a success that is still below the minimum).
final class SpacedMistakeScheduler: QuestionScheduler {
    private let repository: MistakeQueueRepository
    private var queue: [QueuedMistake] = []
    
    init(repository: MistakeQueueRepository) {
        self.repository = repository
        loadQueue()
    }
    
    private func loadQueue() {
        do {
            queue = try repository.loadAll().map { queued in
                var adjusted = queued
                if adjusted.minimumClearanceDistance < 3 {
                    adjusted.minimumClearanceDistance = 3
                }
                if adjusted.currentClearanceDistance < adjusted.minimumClearanceDistance {
                    adjusted.currentClearanceDistance = adjusted.minimumClearanceDistance
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
            return .reask(seed: mistake.seed, settings: mistake.settings, mistakeId: mistake.id)
        }
        
        // No due mistakes, return fresh
        return .fresh
    }
    
    func recordCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, mistakeId: Int64?) {
        if let mistakeId = mistakeId {
            incrementCounters(excluding: mistakeId)
            handleReaskCompletion(mistakeId: mistakeId, hadErrors: hadErrors)
        } else {
            incrementCounters()
            handleFreshCompletion(seed: seed, settings: settings, hadErrors: hadErrors)
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
    
    private func handleFreshCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool) {
        // If the fresh question had errors, add it to the queue
        if hadErrors {
            do {
                let id = try repository.insert(seed: seed, settings: settings)
                let mistake = QueuedMistake(id: id, seed: seed, settings: settings)
                queue.append(mistake)
            } catch {
                // Log error but continue
            }
        }
    }
    
    private func handleReaskCompletion(mistakeId: Int64, hadErrors: Bool) {
        guard let index = queue.firstIndex(where: { $0.id == mistakeId }) else { return }
        
        if hadErrors {
            // Failed the re-ask: bump clearance distance by 3, reset counter
            var mistake = queue[index]
            mistake.minimumClearanceDistance += 3
            mistake.currentClearanceDistance = mistake.minimumClearanceDistance
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
            // Passed the re-ask: clear if we satisfied the minimum, otherwise push out to the minimum spacing.
            var mistake = queue[index]
            mistake.questionsSinceQueued = 0
            if mistake.currentClearanceDistance >= mistake.minimumClearanceDistance {
                queue.remove(at: index)
                do {
                    try repository.delete(id: mistakeId)
                } catch {
                    // Log error but continue
                }
            } else {
                mistake.currentClearanceDistance = mistake.minimumClearanceDistance
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
