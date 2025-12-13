import SwiftUI

struct AccuracyHistorySheet: View {
    let entries: [SequenceHistoryEntry]
    let keyRoot: NoteName

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No History Yet",
                        systemImage: "music.note.list",
                        description: Text("Complete some sequences to see your history here.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                HistoryEntryRow(
                                    entry: entry,
                                    index: index,
                                    totalCount: entries.count,
                                    keyRoot: keyRoot
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Recent Questions")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct HistoryEntryRow: View {
    let entry: SequenceHistoryEntry
    let index: Int
    let totalCount: Int
    let keyRoot: NoteName

    private var hueColor: Color {
        // Spread hues evenly across the entries
        let hue = Double(index) / Double(max(totalCount, 1))
        return Color(hue: hue, saturation: 0.6, brightness: 0.9)
    }

    private var notesString: String {
        entry.midiNotes.map { midiNoteToName($0, keyRoot: keyRoot) }.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(hueColor)
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 4) {
                // Notes
                Text(notesString)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                // Time ago
                Text(timeAgo(from: entry.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Success indicator
            Image(systemName: entry.wasCorrectFirstTry ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(entry.wasCorrectFirstTry ? .green : .red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hueColor.opacity(0.15))
        )
    }

    private func midiNoteToName(_ midi: UInt8, keyRoot: NoteName) -> String {
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
    AccuracyHistorySheet(
        entries: [
            SequenceHistoryEntry(id: 1, midiNotes: [60, 62, 64, 65], wasCorrectFirstTry: true, createdAt: Date().addingTimeInterval(-60)),
            SequenceHistoryEntry(id: 2, midiNotes: [67, 69, 71, 72], wasCorrectFirstTry: false, createdAt: Date().addingTimeInterval(-120)),
            SequenceHistoryEntry(id: 3, midiNotes: [60, 64, 67, 72], wasCorrectFirstTry: true, createdAt: Date().addingTimeInterval(-300)),
        ],
        keyRoot: .c
    )
}
