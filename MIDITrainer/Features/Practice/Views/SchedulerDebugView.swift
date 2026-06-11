import SwiftUI

private enum DebugTab: String, CaseIterable {
    case queue = "Queue"
    case history = "History"
}

struct SchedulerDebugSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: PracticeModel
    @State private var showCopiedFeedback = false
    @State private var selectedTab: DebugTab = .queue

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    ForEach(DebugTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .queue:
                            SchedulerDebugView(model: model)
                        case .history:
                            HistoryDebugView(model: model)
                        }

                        CopyDebugInfoButton(showCopiedFeedback: $showCopiedFeedback) {
                            model.buildDebugInfo().formatted
                        }
                    }
                    .padding()
                }
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
                Text("Clearance: \(model.spacedMistakeClearance) • Min passes: \(model.spacedMistakeMinPasses)")
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

            case .adaptive:
                AdaptiveDebugSection(model: model)
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
        if entry.isActive { return retryLabel }
        if mistake.isDue { return "Ready" }
        return "Waiting"
    }

    private var progress: Double {
        guard mistake.currentClearance > 0 else { return 0 }
        return Double(mistake.questionsWaited) / Double(mistake.currentClearance)
    }

    private var statusColor: Color {
        if entry.isActive { return .green }
        if mistake.isDue { return .orange }
        return .blue
    }

    private var progressDescription: String {
        let remaining = max(0, mistake.currentClearance - mistake.questionsWaited)
        let gap = mistake.currentClearance
        let failText = failureSummary
        if remaining > 0 {
            return "\(failText) • \(remaining) to go • \(gap) gap"
        }
        return "\(failText) • \(gap) gap • Ready"
    }

    private var retryLabel: String {
        guard let totalFailures = mistake.totalFailures else { return "Retry" }
        return "Retry #\(totalFailures)"
    }

    private var failureSummary: String {
        guard let totalFailures = mistake.totalFailures else { return "Failed previously" }
        return "Failed \(totalFailures)x"
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

// MARK: - History Section

private struct HistoryDebugView: View {
    @ObservedObject var model: PracticeModel

    private var queueLookup: [UInt64: SchedulerDebugEntry] {
        Dictionary(uniqueKeysWithValues: model.schedulerDebugEntries.map { ($0.mistake.seed, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Question History")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.sequenceHistory.count) recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if model.sequenceHistory.isEmpty {
                Text("No questions answered yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.sequenceHistory) { entry in
                    HistoryEntryRow(
                        entry: entry,
                        model: model,
                        queueEntry: entry.seed.flatMap { queueLookup[$0] }
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

private struct HistoryEntryRow: View {
    let entry: SequenceHistoryEntry
    @ObservedObject var model: PracticeModel
    let queueEntry: SchedulerDebugEntry?

    private var shortSeed: String {
        guard let seed = entry.seed else { return "----" }
        return String(format: "%04d", seed % 10000)
    }

    private var notesString: String {
        entry.midiNotes.map { midiNoteToName($0) }.joined(separator: " ")
    }

    private var displayName: String {
        entry.sourceName ?? notesString
    }

    private var hasSourceName: Bool {
        entry.sourceName != nil
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("#\(shortSeed)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 40, height: 18)
                .background(entry.wasCorrectFirstTry ? Color.green.opacity(0.8) : Color.red.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 11, design: hasSourceName ? .default : .monospaced))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(timeAgo(from: entry.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let queueEntry {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(reaskDescription(for: queueEntry))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()

            if entry.seed != nil {
                Button {
                    model.previewHistoryEntry(seed: entry.seed!)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }

            Image(systemName: entry.wasCorrectFirstTry ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(entry.wasCorrectFirstTry ? .green : .red)
        }
    }

    private func reaskDescription(for queueEntry: SchedulerDebugEntry) -> String {
        let fails: String
        if let totalFailures = queueEntry.mistake.totalFailures {
            fails = "\(totalFailures)x failed"
        } else {
            fails = "failed before"
        }
        if queueEntry.isActive {
            return "\(fails) • retrying"
        }
        let remaining = queueEntry.remainingUntilDue
        if remaining <= 0 {
            return "\(fails) • ready"
        }
        return "\(fails) • in \(remaining)"
    }

    private func midiNoteToName(_ midi: UInt8) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let noteIndex = Int(midi) % 12
        let octave = Int(midi) / 12 - 1
        return "\(noteNames[noteIndex])\(octave)"
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
