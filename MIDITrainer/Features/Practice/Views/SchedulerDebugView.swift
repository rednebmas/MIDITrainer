import SwiftUI

struct SchedulerDebugView: View {
    let mode: SchedulerMode
    let spacedEntries: [SchedulerDebugEntry]
    let weaknessEntries: [WeaknessEntry]
    let pendingCount: Int
    let questionsUntilNextReask: Int?
    let onClearQueue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Mode header
            HStack {
                Text(mode.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            switch mode {
            case .random:
                Text("Each question is randomly generated")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .spacedMistakes:
                SpacedMistakesDebugSection(
                    entries: spacedEntries,
                    pendingCount: pendingCount,
                    questionsUntilNextReask: questionsUntilNextReask,
                    onClearQueue: onClearQueue
                )

            case .weaknessFocused:
                WeaknessDebugSection(entries: weaknessEntries)

                if pendingCount > 0 {
                    Divider()
                    SpacedMistakesDebugSection(
                        entries: spacedEntries,
                        pendingCount: pendingCount,
                        questionsUntilNextReask: questionsUntilNextReask,
                        onClearQueue: onClearQueue,
                        compact: true
                    )
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
    let entries: [SchedulerDebugEntry]
    let pendingCount: Int
    let questionsUntilNextReask: Int?
    let onClearQueue: () -> Void
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Re-ask Queue")
                        .font(.caption.weight(.medium))
                    if pendingCount > 0 {
                        if let remaining = questionsUntilNextReask, remaining > 0 {
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
                if pendingCount > 0 {
                    Button("Clear") {
                        onClearQueue()
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                }
            }

            if !compact && !entries.isEmpty {
                ForEach(entries) { entry in
                    SpacedMistakeRow(entry: entry)
                }
            }
        }
    }
}

private struct SpacedMistakeRow: View {
    let entry: SchedulerDebugEntry

    private var shortSeed: String {
        String(format: "%04d", entry.seed % 10000)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("#\(shortSeed)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 40, height: 18)
                .background(statusColor.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                Text(statusDescription)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(statusColor)

                Text("\(entry.questionsSinceQueued)/\(entry.currentClearanceDistance) answered")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !entry.isDue && !entry.isActive {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 40)
            }
        }
    }

    private var statusDescription: String {
        if entry.isActive { return "Playing" }
        if entry.isDue { return "Ready" }
        return "Waiting"
    }

    private var progress: Double {
        guard entry.currentClearanceDistance > 0 else { return 0 }
        return Double(entry.questionsSinceQueued) / Double(entry.currentClearanceDistance)
    }

    private var statusColor: Color {
        if entry.isActive { return .green }
        if entry.isDue { return .orange }
        return .blue
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
        SchedulerDebugView(
            mode: .weaknessFocused,
            spacedEntries: [],
            weaknessEntries: [
                WeaknessEntry(seed: 12345, timesAsked: 5, firstAttemptFailures: 3),
                WeaknessEntry(seed: 67890, timesAsked: 10, firstAttemptFailures: 2)
            ],
            pendingCount: 1,
            questionsUntilNextReask: 2,
            onClearQueue: {}
        )

        SchedulerDebugView(
            mode: .spacedMistakes,
            spacedEntries: [],
            weaknessEntries: [],
            pendingCount: 0,
            questionsUntilNextReask: nil,
            onClearQueue: {}
        )
    }
    .padding()
}
