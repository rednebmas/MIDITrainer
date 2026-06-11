import SwiftUI

struct AdaptiveDebugSection: View {
    let snapshot: AdaptiveDebugSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Difficulty dial: \(percent(snapshot.dialValue)) • target \(percent(snapshot.targetAccuracy))")
                    .font(.caption.weight(.medium))
                if let rolling = snapshot.rollingAccuracy {
                    Text("Rolling first-guess accuracy: \(percent(rolling))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Rolling accuracy: warming up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if snapshot.fragments.isEmpty {
                Text("No fragment drills queued")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Fragment Drills (\(snapshot.fragments.count))")
                    .font(.caption.weight(.medium))
                ForEach(snapshot.fragments) { fragment in
                    FragmentDebugRow(fragment: fragment)
                }
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct FragmentDebugRow: View {
    let fragment: QueuedFragment

    private var name: String {
        let interval = IntervalName.label(semitones: fragment.intervalSemitones)
        guard let source = fragment.sourceName else { return interval }
        return "\(interval) · \(source)"
    }

    private var status: String {
        let streak = "streak \(fragment.consecutiveCorrect)/\(AdaptiveTuning.clearStreak)"
        let due = fragment.isDue
            ? "ready"
            : "due in \(AdaptiveTuning.fragmentSpacing - fragment.questionsSinceAsked)"
        return "\(streak) • \(due) • failed \(fragment.totalFailures)x"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background((fragment.isDue ? Color.orange : Color.purple).opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(status)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}
