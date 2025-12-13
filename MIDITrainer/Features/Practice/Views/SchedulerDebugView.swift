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
                    ForEach(entries) { entry in
                        MistakeEntryRow(entry: entry)
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

    // Use last 4 digits of ID as a stable short identifier
    private var shortId: String {
        String(format: "%04d", entry.id % 10000)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Stable ID badge
            Text("#\(shortId)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 40, height: 20)
                .background(statusColor.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                // Status
                Text(statusDescription)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)

                // Progress info with clearance details
                Text(progressDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Clearance debug info
                Text("min: \(entry.minimumClearanceDistance), current: \(entry.currentClearanceDistance), answered: \(entry.questionsSinceQueued)")
                    .font(.system(size: 12, design: .monospaced))
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
