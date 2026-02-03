import SwiftUI

struct SchedulerDebugSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: PracticeModel
    @State private var showCopiedFeedback = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SchedulerDebugView(model: model)

                    CopyDebugInfoButton(showCopiedFeedback: $showCopiedFeedback) {
                        model.buildDebugInfo().formatted
                    }
                }
                .padding()
            }
            .navigationTitle("Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CopyDebugInfoButton: View {
    @Binding var showCopiedFeedback: Bool
    let getDebugInfo: () -> String

    var body: some View {
        Button {
            let info = getDebugInfo()
            UIPasteboard.general.string = info
            showCopiedFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopiedFeedback = false
            }
        } label: {
            HStack {
                Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                Text(showCopiedFeedback ? "Copied!" : "Copy Debug Info")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(showCopiedFeedback ? .green : .blue)
    }
}

struct SchedulerDebugView: View {
    @ObservedObject var model: PracticeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.schedulerMode.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Clearance: \(model.spacedMistakeClearance)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch model.schedulerMode {
            case .random:
                Text("Each question is randomly generated")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .spacedMistakes:
                SpacedMistakesDebugSection(model: model, compact: false)

            case .weaknessFocused:
                WeaknessDebugSection(entries: model.weaknessDebugEntries)

                if model.pendingMistakeCount > 0 {
                    Divider()
                    SpacedMistakesDebugSection(model: model, compact: true)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

// MARK: - Spaced Mistakes Section

private struct SpacedMistakesDebugSection: View {
    @ObservedObject var model: PracticeModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Re-ask Queue")
                        .font(.caption.weight(.medium))
                    if model.pendingMistakeCount > 0 {
                        if let remaining = model.questionsUntilNextReask, remaining > 0 {
                            Text("Next in \(remaining) question\(remaining == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Ready now")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text("No mistakes queued")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.pendingMistakeCount > 0 {
                    Button("Clear") {
                        model.clearMistakeQueue()
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                }
            }

            if !compact && !model.schedulerDebugEntries.isEmpty {
                let sortedEntries = model.schedulerDebugEntries.sorted { a, b in
                    if a.isActive != b.isActive { return a.isActive }
                    return a.remainingUntilDue < b.remainingUntilDue
                }
                ForEach(sortedEntries) { entry in
                    SpacedMistakeRow(entry: entry)
                }
            }
        }
    }
}

private struct SpacedMistakeRow: View {
    let entry: SchedulerDebugEntry

    private var mistake: QueuedMistake { entry.mistake }

    private var shortSeed: String {
        String(format: "%04d", mistake.seed % 10000)
    }

    private var displayName: String {
        mistake.sourceName ?? "#\(shortSeed)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(displayName)
                .font(.system(size: 10, weight: .semibold, design: mistake.sourceName == nil ? .monospaced : .default))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(statusColor.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                Text(statusDescription)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor)

                Text(progressDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !mistake.isDue && !entry.isActive {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 40)
            }
        }
    }

    private var statusDescription: String {
        if entry.isActive { return "Retry #\(mistake.totalFailures)" }
        if mistake.isDue { return "Ready" }
        return "Waiting"
    }

    private var progress: Double {
        guard mistake.currentClearanceDistance > 0 else { return 0 }
        return Double(mistake.questionsSinceQueued) / Double(mistake.currentClearanceDistance)
    }

    private var statusColor: Color {
        if entry.isActive { return .green }
        if mistake.isDue { return .orange }
        return .blue
    }

    private var progressDescription: String {
        let remaining = mistake.currentClearanceDistance - mistake.questionsSinceQueued
        let gap = mistake.currentClearanceDistance
        let failText = "Failed \(mistake.totalFailures)x"
        return remaining > 0 ? "\(failText) • \(remaining) to go • \(gap) gap" : "\(failText) • Ready"
    }
}

// MARK: - Weakness Section

private struct WeaknessDebugSection: View {
    let entries: [WeaknessEntry]

    private var totalWeight: Double {
        entries.reduce(0) { $0 + $1.weight }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Historical Weaknesses (\(entries.count) seeds)")
                .font(.caption.weight(.medium))

            if entries.isEmpty {
                Text("No weaknesses recorded yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries, id: \.seed) { entry in
                    WeaknessRow(entry: entry, totalWeight: totalWeight)
                }
            }
        }
    }
}

private struct WeaknessRow: View {
    let entry: WeaknessEntry
    let totalWeight: Double

    private var probability: Double {
        guard totalWeight > 0 else { return 0 }
        return entry.weight / totalWeight * 100
    }

    private var shortSeed: String {
        String(format: "%04d", entry.seed % 10000)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("#\(shortSeed)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 40, height: 18)
                .background(Color.orange.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                Text("\(entry.firstAttemptFailures) mistakes / \(entry.timesAsked) tries")
                    .font(.caption2)

                Text(String(format: "%.0f%% chance", probability))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange.opacity(0.6))
                .frame(width: CGFloat(min(probability, 100)) * 0.4, height: 6)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        WeaknessDebugSection(entries: [
            WeaknessEntry(seed: 12345, timesAsked: 5, firstAttemptFailures: 3),
            WeaknessEntry(seed: 67890, timesAsked: 10, firstAttemptFailures: 2)
        ])
    }
    .padding()
}
