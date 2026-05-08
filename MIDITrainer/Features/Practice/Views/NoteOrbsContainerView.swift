import SwiftUI

struct NoteOrbsContainerView: View {
    @ObservedObject var model: PracticeModel

    @SwiftUI.State private var appearingOrbs: Set<Int> = []
    @SwiftUI.State private var displayedAwaitingIndex: Int?

    private var sequence: MelodySequence? { model.currentSequence }

    private var firstNoteName: String? {
        guard let midiNumber = sequence?.notes.first?.midiNoteNumber,
              let noteName = NoteName(rawValue: Int(midiNumber % 12)) else { return nil }
        return noteName.displayName
    }

    private var statusText: String {
        guard sequence != nil else { return "Press Start to begin" }
        if model.isPlaying {
            return model.isReplaying ? "Replaying..." : "Playing..."
        } else {
            return "Your turn..."
        }
    }

    private var chordSymbolsText: String? {
        guard model.showChordSymbols,
              let chords = sequence?.chords,
              !chords.isEmpty else { return nil }
        var seen = Set<String>()
        var result: [String] = []
        for chord in chords {
            if !seen.contains(chord.chord) {
                seen.insert(chord.chord)
                result.append(chord.chord)
            }
        }
        return result.joined(separator: " → ")
    }

    private var answerNoteNames: [String]? {
        guard let notes = sequence?.notes else { return nil }
        return notes.compactMap { NoteName(rawValue: Int($0.midiNoteNumber % 12))?.displayName }
    }

    var body: some View {
        VStack(spacing: 24) {
            if let sequence = sequence {
                if model.showNoteOrbs {
                    HStack(spacing: 16) {
                        ForEach(Array(sequence.notes.enumerated()), id: \.offset) { index, _ in
                            NoteOrbView(state: orbState(for: index), index: index)
                                .opacity(appearingOrbs.contains(index) ? 1 : 0)
                                .scaleEffect(appearingOrbs.contains(index) ? 1 : 0.5)
                        }
                    }
                    .onChange(of: sequence.seed) { _, _ in
                        animateOrbsAppearance(count: sequence.notes.count)
                    }
                    .onAppear {
                        animateOrbsAppearance(count: sequence.notes.count)
                    }
                } else if model.isShowingAnswer, let names = answerNoteNames {
                    HStack(spacing: 20) {
                        ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                            Text(name)
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                    }
                } else {
                    Text(statusText)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    if let name = firstNoteName {
                        HStack(spacing: 6) {
                            Image(systemName: "music.note")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                            Text("First note:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                    }

                    if let source = sequence.sourceName {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(source)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let chords = chordSymbolsText {
                        HStack(spacing: 6) {
                            Image(systemName: "pianokeys")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(chords)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    #if DEBUG
                    HStack(spacing: 4) {
                        if let gap = model.activeMistakeCurrentGap {
                            Text("Retry\(model.activeMistakeTotalFailures.map { " #\($0)" } ?? "") (gap \(gap))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.yellow)
                        } else if model.isReplaying {
                            Text("Replay #\(model.currentAttemptNumber)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        } else {
                            Text("NEW")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.top, 4)
                    #endif
                }
                .padding(.top, 8)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "pianokeys")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Press Start to begin")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .onChange(of: model.keysAreHeld) { _, keysHeld in
            if !keysHeld {
                displayedAwaitingIndex = model.awaitingNoteIndex
            }
        }
        .onChange(of: model.currentSequence?.seed) { _, _ in
            displayedAwaitingIndex = model.awaitingNoteIndex
        }
    }

    private func orbState(for index: Int) -> NoteOrbView.State {
        if let errorIdx = model.errorNoteIndex, errorIdx == index {
            return .error
        }

        guard let awaiting = displayedAwaitingIndex else {
            return .correct
        }

        if index < awaiting {
            return .correct
        } else if index == awaiting {
            return .awaiting
        } else {
            return .pending
        }
    }

    private func animateOrbsAppearance(count: Int) {
        appearingOrbs.removeAll()

        for i in 0..<count {
            let delay = Double(i) * 0.06
            _ = withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(delay)) {
                appearingOrbs.insert(i)
            }
        }
    }
}
