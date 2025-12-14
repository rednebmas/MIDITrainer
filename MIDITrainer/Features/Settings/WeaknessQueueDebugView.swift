import SwiftUI

struct WeaknessQueueDebugView: View {
    let settings: PracticeSettingsSnapshot
    var matchExactSettings: Bool = false

    private var weaknessEntries: [WeaknessEntry] {
        guard let db = try? Database(),
              let entries = try? StatsRepository(db: db).topWeaknesses(
                for: settings,
                limit: 20,
                matchExactSettings: matchExactSettings
              ) else {
            return []
        }
        return entries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weakness Queue (\(weaknessEntries.count) seeds)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if weaknessEntries.isEmpty {
                Text("No weaknesses recorded yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(weaknessEntries, id: \.seed) { entry in
                    WeaknessEntryRow(entry: entry, totalWeight: totalWeight)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var totalWeight: Double {
        weaknessEntries.reduce(0) { $0 + $1.weight }
    }
}

private struct WeaknessEntryRow: View {
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
                    .font(.caption)

                Text(String(format: "%.0f%% chance", probability))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Visual weight indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange.opacity(0.6))
                .frame(width: CGFloat(min(probability, 100)) * 0.5, height: 8)
        }
    }
}
