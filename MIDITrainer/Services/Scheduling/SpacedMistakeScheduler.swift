import Foundation

/// A scheduler that reinforces incorrect sequences by re-asking them after spaced intervals.
/// 
/// Behavior:
/// - When a sequence is answered incorrectly, it's added to the queue with clearance distance 1.
/// - After finishing an incorrect sequence, a fresh question is always asked next.
/// - After the required number of fresh questions, the mistake is re-asked.
/// - If answered correctly on re-ask, it's removed from the queue.
/// - If answered incorrectly on re-ask, clearance distance is multiplied by 3 and it's requeued.
final class SpacedMistakeScheduler: QuestionScheduler {
    private let repository: MistakeQueueRepository
    private var queue: [QueuedMistake] = []
    private var justAskedFresh: Bool = false
    
    init(repository: MistakeQueueRepository) {
        self.repository = repository
        loadQueue()
    }
    
    private func loadQueue() {
        do {
            queue = try repository.loadAll()
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
            // This was a re-ask
            handleReaskCompletion(mistakeId: mistakeId, hadErrors: hadErrors)
        } else {
            // This was a fresh question
            handleFreshCompletion(seed: seed, settings: settings, hadErrors: hadErrors)
        }
    }
    
    private func handleFreshCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool) {
        // Increment counters for all queued mistakes
        do {
            try repository.incrementAllCounters()
            for i in queue.indices {
                queue[i].questionsSinceQueued += 1
            }
        } catch {
            // Log error but continue
        }
        
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
            // Failed the re-ask: multiply clearance distance by 3, reset counter
            var mistake = queue[index]
            mistake.clearanceDistance *= 3
            mistake.questionsSinceQueued = 0
            queue[index] = mistake
            
            do {
                try repository.update(
                    id: mistakeId,
                    clearanceDistance: mistake.clearanceDistance,
                    questionsSinceQueued: 0
                )
            } catch {
                // Log error but continue
            }
        } else {
            // Passed the re-ask: remove from queue
            queue.remove(at: index)
            do {
                try repository.delete(id: mistakeId)
            } catch {
                // Log error but continue
            }
        }
    }
    
    var pendingCount: Int {
        queue.count
    }
    
    var questionsUntilNextReask: Int? {
        // Find the minimum remaining questions until any mistake is due
        let remaining = queue.compactMap { mistake -> Int? in
            let remaining = mistake.clearanceDistance - mistake.questionsSinceQueued
            return remaining > 0 ? remaining : nil
        }
        return remaining.min()
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
