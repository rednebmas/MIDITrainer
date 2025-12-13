import SwiftUI

struct SchedulerDebugView: View {
    let entries: [SchedulerDebugEntry]
    let pendingCount: Int
    let questionsUntilNextReask: Int?
    let onClearQueue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with summary
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Re-ask Queue")
                        .font(.subheadline.weight(.medium))
                    if pendingCount > 0 {
                        if let remaining = questionsUntilNextReask, remaining > 0 {
                            Text("Next re-ask in \(remaining) question\(remaining == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Re-ask ready now")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text("No mistakes queued")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if pendingCount > 0 {
                    Button("Clear All") {
                        onClearQueue()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            // Queued mistakes list
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        MistakeEntryRow(entry: entry, index: index + 1)
                    }
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

struct MistakeEntryRow: View {
    let entry: SchedulerDebugEntry
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            // Index badge
            Text("#\(index)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 20)
                .background(statusColor.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                // Status
                Text(statusDescription)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)

                // Progress info
                Text(progressDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Visual progress indicator
            if !entry.isDue && !entry.isActive {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 50)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusDescription: String {
        if entry.isActive { return "Now playing" }
        if entry.isDue { return "Ready to play" }
        return "Waiting (\(entry.remainingUntilDue) more)"
    }

    private var progressDescription: String {
        if entry.isActive { return "Testing your recall" }
        if entry.isDue { return "Will be asked next" }
        return "Answered \(entry.questionsSinceQueued) of \(entry.currentClearanceDistance) needed"
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

#Preview {
    SchedulerDebugView(
        entries: [],
        pendingCount: 2,
        questionsUntilNextReask: 3,
        onClearQueue: {}
    )
    .padding()
}
