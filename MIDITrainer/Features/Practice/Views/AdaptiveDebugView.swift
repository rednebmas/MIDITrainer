import SwiftUI

struct AdaptiveDebugSection: View {
    @ObservedObject var model: PracticeModel

    var body: some View {
        if let snapshot = model.adaptiveDebugSnapshot {
            VStack(alignment: .leading, spacing: 12) {
                dialReadout(snapshot)
                fragmentList(snapshot)
                melodyList(snapshot)
            }
        }
    }

    private func dialReadout(_ snapshot: AdaptiveDebugSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Difficulty dial: \(percent(snapshot.dialValue)) • target \(percent(snapshot.targetAccuracy))")
                .font(.caption.weight(.medium))
            Text(snapshot.rollingAccuracy.map { "Rolling first-guess accuracy: \(percent($0))" }
                ?? "Rolling accuracy: warming up")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func fragmentList(_ snapshot: AdaptiveDebugSnapshot) -> some View {
        if snapshot.fragments.isEmpty {
            Text("No fragment drills queued")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("Fragment Drills (\(snapshot.fragments.count))")
                .font(.caption.weight(.medium))
            ForEach(snapshot.fragments) { fragment in
                FragmentDebugRow(fragment: fragment, isActive: fragment.id == model.activeDrill?.id)
            }
        }
    }

    @ViewBuilder
    private func melodyList(_ snapshot: AdaptiveDebugSnapshot) -> some View {
        if !model.schedulerDebugEntries.isEmpty {
            HStack {
                Text("Melody Queue (\(model.schedulerDebugEntries.count))")
                    .font(.caption.weight(.medium))
                Spacer()
                Button("Clear") { model.clearMistakeQueue() }
                    .font(.caption2)
                    .buttonStyle(.bordered)
            }
            ForEach(model.schedulerDebugEntries) { entry in
                AdaptiveMelodyRow(
                    entry: entry,
                    openDrills: snapshot.fragments.lazy.filter { $0.parentMistakeId == entry.id }.count,
                    clearance: model.spacedMistakeClearance,
                    minPasses: model.spacedMistakeMinPasses
                )
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct AdaptiveMelodyRow: View {
    let entry: SchedulerDebugEntry
    let openDrills: Int
    let clearance: Int
    let minPasses: Int

    private var displayName: String {
        entry.mistake.sourceName ?? String(format: "#%04d", entry.mistake.seed % 10000)
    }

    private var ladderProgress: String {
        let rung = max(1, entry.mistake.currentClearance / max(1, clearance))
        let required = max(minPasses, entry.mistake.totalFailures ?? 1)
        return "pass \(rung)/\(required)"
    }

    private var status: (text: String, color: Color) {
        if entry.isActive { return ("Rescue now", .green) }
        if openDrills > 0 { return ("Gated • \(openDrills) drill\(openDrills == 1 ? "" : "s") open", .purple) }
        if entry.remainingUntilDue > 0 { return ("Waiting • \(entry.remainingUntilDue) to go", .blue) }
        return ("Rescue ready", .orange)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(status.color.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text("\(status.text) • \(ladderProgress) • failed \(entry.mistake.totalFailures ?? 1)x")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

private struct FragmentDebugRow: View {
    let fragment: QueuedFragment
    let isActive: Bool

    private var name: String {
        let interval = IntervalName.label(semitones: fragment.intervalSemitones)
        guard let source = fragment.sourceName else { return interval }
        return "\(interval) · \(source)"
    }

    private var status: String {
        if isActive { return "drilling now" }
        let streak = "streak \(fragment.consecutiveCorrect)/\(AdaptiveTuning.clearStreak)"
        let due = fragment.isDue
            ? "ready"
            : "due in \(AdaptiveTuning.fragmentSpacing - fragment.questionsSinceAsked)"
        return "\(streak) • \(due) • failed \(fragment.totalFailures)x"
    }

    private var chipColor: Color {
        if isActive { return .green }
        return fragment.isDue ? .orange : .purple
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(chipColor.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}
