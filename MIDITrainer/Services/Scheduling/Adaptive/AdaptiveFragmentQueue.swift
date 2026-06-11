import Foundation

/// In-memory fragment queue backed by FragmentQueueRepository.
///
/// Fragments are deduplicated by identity (same degree transition = same
/// skill): re-extracting an existing identity for the same parent resets its
/// streak instead of inserting, and ask results apply to every row sharing
/// the asked fragment's identity so the user never grinds one interval twice.
final class AdaptiveFragmentQueue {
    private let repository: FragmentQueueRepository
    private let octaveMatters: () -> Bool
    private(set) var fragments: [QueuedFragment] = []

    init(repository: FragmentQueueRepository, octaveMatters: @escaping () -> Bool) {
        self.repository = repository
        self.octaveMatters = octaveMatters
        reload()
    }

    func reload() {
        fragments = (try? repository.loadAll()) ?? []
    }

    var dueFragment: QueuedFragment? {
        fragments.first { $0.isDue }
    }

    func fragment(id: Int64) -> QueuedFragment? {
        fragments.first { $0.id == id }
    }

    func fragmentCount(forParent parentId: Int64) -> Int {
        fragments.lazy.filter { $0.parentMistakeId == parentId }.count
    }

    /// Queues extracted fragments, deduplicating against existing rows for the
    /// same parent. Returns the ids backing each extracted fragment.
    func enqueue(_ extracted: [ExtractedFragment], parentMistakeId: Int64?, sourceName: String?) -> [Int64] {
        var ids: [Int64] = []
        for fragment in extracted {
            let identity = fragment.identity(octaveMatters: octaveMatters())
            if let index = fragments.firstIndex(where: {
                $0.parentMistakeId == parentMistakeId && $0.identity(octaveMatters: octaveMatters()) == identity
            }) {
                fragments[index].consecutiveCorrect = 0
                fragments[index].totalFailures += 1
                persist(fragments[index])
                ids.append(fragments[index].id)
            } else if let row = try? repository.insert(fragment, parentMistakeId: parentMistakeId, sourceName: sourceName) {
                fragments.append(row)
                ids.append(row.id)
            }
        }
        return ids
    }

    /// Applies a drill result to all rows sharing the asked fragment's
    /// identity. Returns parents whose last open fragment just cleared.
    func recordResult(fragmentId: Int64, passed: Bool) -> [Int64] {
        guard let asked = fragment(id: fragmentId) else { return [] }
        let identity = asked.identity(octaveMatters: octaveMatters())
        var clearedParents: Set<Int64> = []
        var remaining: [QueuedFragment] = []

        for var row in fragments {
            guard row.identity(octaveMatters: octaveMatters()) == identity else {
                remaining.append(row)
                continue
            }
            row.questionsSinceAsked = 0
            if passed {
                row.consecutiveCorrect += 1
                if row.consecutiveCorrect >= AdaptiveTuning.clearStreak {
                    try? repository.delete(id: row.id)
                    if let parent = row.parentMistakeId {
                        clearedParents.insert(parent)
                    }
                    continue
                }
            } else {
                row.consecutiveCorrect = 0
                row.totalFailures += 1
            }
            persist(row)
            remaining.append(row)
        }

        fragments = remaining
        return clearedParents.filter { fragmentCount(forParent: $0) == 0 }
    }

    func incrementCounters(excluding excludedId: Int64? = nil) {
        try? repository.incrementAllCounters(excluding: excludedId)
        for index in fragments.indices where fragments[index].id != excludedId {
            fragments[index].questionsSinceAsked += 1
        }
    }

    /// Removes a fragment that can no longer be rendered (e.g. out of MIDI range).
    func remove(id: Int64) {
        try? repository.delete(id: id)
        fragments.removeAll { $0.id == id }
    }

    func clear() {
        try? repository.deleteAll()
        fragments = []
    }

    private func persist(_ row: QueuedFragment) {
        try? repository.update(
            id: row.id,
            consecutiveCorrect: row.consecutiveCorrect,
            questionsSinceAsked: row.questionsSinceAsked,
            totalFailures: row.totalFailures
        )
    }
}
