import Foundation

struct AdaptiveDebugSnapshot {
    let dialValue: Double
    let targetAccuracy: Double
    let rollingAccuracy: Double?
    let fragments: [QueuedFragment]
    let gatedParentIds: Set<Int64>
}

/// Keeps practice near the user's target accuracy and remediates failures
/// with 2-note fragment drills instead of grinding full melodies.
///
/// Question priority: immediate drills (optional) → due spaced fragments →
/// rescue re-asks of melodies whose fragments are cleared → fresh melodies
/// generated at the difficulty dial. Melodies are never retired: they leave
/// the queue only by climbing the same spaced-success ladder as
/// spacedMistakes mode (clearance × max(minPasses, failures)), with fragment
/// drills remediating the underlying interval between attempts.
final class AdaptiveScheduler: QuestionScheduler {
    private let mistakeRepository: MistakeQueueRepository
    private let fragmentQueue: AdaptiveFragmentQueue
    private let statsRepository: StatsRepository
    private let seedPicker: DifficultyTargetedSeedPicker
    private let extractor = FragmentExtractor()
    private let targetAccuracy: () -> Double
    private let clearanceProvider: () -> Int
    private let minPassesProvider: () -> Int
    private let immediateDrills: () -> Bool
    private let dial: DifficultyDial
    private var melodyQueue: [QueuedMistake] = []
    private var pendingImmediateFragmentIds: [Int64] = []

    init(
        mistakeRepository: MistakeQueueRepository,
        fragmentQueue: AdaptiveFragmentQueue,
        statsRepository: StatsRepository,
        seedPicker: DifficultyTargetedSeedPicker = DifficultyTargetedSeedPicker(),
        targetAccuracy: @escaping () -> Double,
        clearance: @escaping () -> Int = { 3 },
        minPasses: @escaping () -> Int = { 3 },
        immediateDrills: @escaping () -> Bool = { false }
    ) {
        self.mistakeRepository = mistakeRepository
        self.fragmentQueue = fragmentQueue
        self.statsRepository = statsRepository
        self.seedPicker = seedPicker
        self.targetAccuracy = targetAccuracy
        self.clearanceProvider = clearance
        self.minPassesProvider = minPasses
        self.immediateDrills = immediateDrills
        let warmStart = (try? statsRepository.recentFirstGuessResults(
            filter: .allKeys, limit: AdaptiveTuning.rollingWindowSize
        )) ?? []
        self.dial = DifficultyDial(target: targetAccuracy, seedResults: warmStart)
        self.melodyQueue = []
        self.melodyQueue = loadMelodyQueue()
    }

    private func loadMelodyQueue() -> [QueuedMistake] {
        ((try? mistakeRepository.loadAll()) ?? []).map { mistake in
            var adjusted = mistake
            adjusted.minimumClearanceDistance = requiredDistance(for: adjusted)
            adjusted.currentClearanceDistance = min(
                max(clearance, adjusted.currentClearanceDistance),
                adjusted.minimumClearanceDistance
            )
            return adjusted
        }
    }

    private func requiredDistance(for mistake: QueuedMistake) -> Int {
        mistake.requiredClearanceDistance(clearance: clearance, minPasses: minPasses)
    }

    private var clearance: Int { max(1, clearanceProvider()) }
    private var minPasses: Int { max(1, minPassesProvider()) }

    // MARK: - QuestionScheduler

    func nextQuestion(currentSettings: PracticeSettingsSnapshot) -> NextQuestion {
        if let drill = nextImmediateDrill(settings: currentSettings) {
            return .fragment(drill)
        }
        if let due = fragmentQueue.dueFragment {
            if let drill = resolveDrill(due, settings: currentSettings) {
                return .fragment(drill)
            }
            fragmentQueue.remove(id: due.id)
        }
        if let rescue = melodyQueue.first(where: { isRescueDue($0) }) {
            return .reask(seed: rescue.seed, settings: currentSettings, mistakeId: rescue.id)
        }
        return freshQuestion(settings: currentSettings)
    }

    func record(_ report: CompletionReport) {
        fragmentQueue.incrementCounters(excluding: report.question.fragmentId)
        incrementMelodyCounters(excluding: report.question.mistakeId)
        dial.record(noteResults: report.firstGuessResults)

        switch report.question {
        case .fresh:
            handleFreshCompletion(report)
        case .reask(let mistakeId):
            handleRescueCompletion(mistakeId: mistakeId, report: report)
        case .fragment(let fragmentId):
            let cleared = fragmentQueue.recordResult(fragmentId: fragmentId, passed: !report.hadErrors)
            for parentId in cleared {
                armRescue(parentId: parentId)
            }
        }
    }

    func recordCompletion(seed: UInt64, settings: PracticeSettingsSnapshot, hadErrors: Bool, mistakeId: Int64?, sourceName: String?) {
        record(CompletionReport(
            seed: seed,
            settings: settings,
            hadErrors: hadErrors,
            question: mistakeId.map { .reask(mistakeId: $0) } ?? .fresh,
            sourceName: sourceName,
            notes: [],
            firstAttemptFailedIndices: []
        ))
    }

    var pendingCount: Int {
        melodyQueue.count + fragmentQueue.fragments.count
    }

    var questionsUntilNextReask: Int? {
        let remaining = melodyQueue
            .filter { fragmentQueue.fragmentCount(forParent: $0.id) == 0 }
            .map { $0.currentClearanceDistance - $0.questionsSinceQueued }
            .filter { $0 > 0 }
        return remaining.min()
    }

    var queueSnapshot: [QueuedMistake] {
        melodyQueue
    }

    func clearQueue() {
        try? mistakeRepository.deleteAll()
        melodyQueue = []
        fragmentQueue.clear()
        pendingImmediateFragmentIds = []
    }

    func reload() {
        melodyQueue = loadMelodyQueue()
        fragmentQueue.reload()
        pendingImmediateFragmentIds = []
    }

    var debugSnapshot: AdaptiveDebugSnapshot {
        AdaptiveDebugSnapshot(
            dialValue: dial.value,
            targetAccuracy: targetAccuracy(),
            rollingAccuracy: dial.rollingAccuracy,
            fragments: fragmentQueue.fragments,
            gatedParentIds: Set(fragmentQueue.fragments.compactMap(\.parentMistakeId))
        )
    }

    // MARK: - Question selection

    private func nextImmediateDrill(settings: PracticeSettingsSnapshot) -> FragmentDrill? {
        while immediateDrills(), !pendingImmediateFragmentIds.isEmpty {
            let id = pendingImmediateFragmentIds.removeFirst()
            guard let fragment = fragmentQueue.fragment(id: id) else { continue }
            if let drill = resolveDrill(fragment, settings: settings) {
                return drill
            }
            fragmentQueue.remove(id: id)
        }
        return nil
    }

    private func isRescueDue(_ mistake: QueuedMistake) -> Bool {
        mistake.questionsSinceQueued >= mistake.currentClearanceDistance
            && fragmentQueue.fragmentCount(forParent: mistake.id) == 0
    }

    private func freshQuestion(settings: PracticeSettingsSnapshot) -> NextQuestion {
        let predictor = MelodyAccuracyPredictor(stats: intervalStats())
        let seed = seedPicker.pickSeed(
            settings: settings,
            dial: dial.value,
            predictor: predictor,
            masterSeed: UInt64.random(in: .min ... .max)
        )
        return .fresh(seed: seed)
    }

    private func intervalStats() -> FirstGuessIntervalStats {
        let empty = FirstGuessIntervalStats(intervals: [], start: nil)
        let since = Date().addingTimeInterval(-AdaptiveTuning.statsRecencyDays * 86400)
        let recent = (try? statsRepository.firstGuessAccuracyByInterval(filter: .allKeys, since: since)) ?? empty
        if recent.totalAttempts >= AdaptiveTuning.minRecentAttempts {
            return recent
        }
        return (try? statsRepository.firstGuessAccuracyByInterval(filter: .allKeys, since: nil)) ?? recent
    }

    /// Renders a fragment's degree/octave pair in the current key, shifting
    /// whole octaves if needed to fit the allowed range.
    private func resolveDrill(_ fragment: QueuedFragment, settings: PracticeSettingsSnapshot) -> FragmentDrill? {
        let scale = Scale(key: settings.key, type: settings.scaleType)
        let octaves = settings.allowedOctaves.isEmpty ? [4] : settings.allowedOctaves
        let nearest = octaves.min {
            abs($0 - fragment.fromOctave) < abs($1 - fragment.fromOctave)
        } ?? fragment.fromOctave
        let delta = nearest - fragment.fromOctave
        guard let from = scale.midiNoteNumber(for: fragment.fromDegree, octave: fragment.fromOctave + delta),
              let to = scale.midiNoteNumber(for: fragment.toDegree, octave: fragment.toOctave + delta) else {
            return nil
        }
        var label = "\(IntervalName.label(semitones: Int(to) - Int(from))) drill"
        if let source = fragment.sourceName {
            label += " from \(source)"
        }
        return FragmentDrill(fragmentId: fragment.id, midiNotes: [from, to], label: label)
    }

    // MARK: - Completion handling

    private func handleFreshCompletion(_ report: CompletionReport) {
        guard report.hadErrors, let seed = report.seed else { return }
        guard let mistake = try? mistakeRepository.insert(
            seed: seed,
            settings: report.settings,
            sourceName: report.sourceName,
            clearance: clearance
        ) else { return }
        melodyQueue.append(mistake)
        queueFragments(from: report, parentMistakeId: mistake.id)
    }

    /// Success climbs the same spaced-repetition ladder as spacedMistakes
    /// mode: each pass widens the gap by one clearance unit, clearing once it
    /// reaches clearance × max(minPasses, totalFailures) — so failures inflate
    /// the required proof. Failure steps the ladder back one rung (floor at
    /// base) and additionally re-gates the melody behind fragment drills.
    private func handleRescueCompletion(mistakeId: Int64, report: CompletionReport) {
        guard let index = melodyQueue.firstIndex(where: { $0.id == mistakeId }) else { return }
        melodyQueue[index].questionsSinceQueued = 0
        if report.hadErrors {
            melodyQueue[index].totalFailures = (melodyQueue[index].totalFailures ?? 1) + 1
            melodyQueue[index].currentClearanceDistance = max(
                clearance, melodyQueue[index].currentClearanceDistance - clearance
            )
            melodyQueue[index].minimumClearanceDistance = requiredDistance(for: melodyQueue[index])
            persist(melodyQueue[index])
            queueFragments(from: report, parentMistakeId: mistakeId)
        } else if melodyQueue[index].currentClearanceDistance >= requiredDistance(for: melodyQueue[index]) {
            try? mistakeRepository.delete(id: mistakeId)
            melodyQueue.remove(at: index)
        } else {
            melodyQueue[index].currentClearanceDistance += clearance
            melodyQueue[index].minimumClearanceDistance = requiredDistance(for: melodyQueue[index])
            persist(melodyQueue[index])
        }
    }

    private func queueFragments(from report: CompletionReport, parentMistakeId: Int64) {
        let scale = Scale(key: report.settings.key, type: report.settings.scaleType)
        let extracted = extractor.extract(
            notes: report.notes,
            failedIndices: report.firstAttemptFailedIndices,
            scale: scale
        )
        let ids = fragmentQueue.enqueue(extracted, parentMistakeId: parentMistakeId, sourceName: report.sourceName)
        if immediateDrills() {
            pendingImmediateFragmentIds = ids
        }
    }

    private func armRescue(parentId: Int64) {
        guard let index = melodyQueue.firstIndex(where: { $0.id == parentId }) else { return }
        melodyQueue[index].questionsSinceQueued = 0
        persist(melodyQueue[index])
    }

    private func incrementMelodyCounters(excluding excludedId: Int64?) {
        try? mistakeRepository.incrementAllCounters(excluding: excludedId)
        for index in melodyQueue.indices where melodyQueue[index].id != excludedId {
            melodyQueue[index].questionsSinceQueued += 1
        }
    }

    private func persist(_ mistake: QueuedMistake) {
        try? mistakeRepository.update(
            id: mistake.id,
            minimumClearanceDistance: mistake.minimumClearanceDistance,
            currentClearanceDistance: mistake.currentClearanceDistance,
            totalFailures: mistake.totalFailures,
            questionsSinceQueued: mistake.questionsSinceQueued
        )
    }
}
