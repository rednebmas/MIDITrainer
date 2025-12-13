import SwiftUI

struct NoteOrbsContainerView: View {
    let sequence: MelodySequence?
    let awaitingIndex: Int?
    let errorIndex: Int?
    let isPlaying: Bool
    let firstNoteName: String?

    @SwiftUI.State private var appearingOrbs: Set<Int> = []

    var body: some View {
        VStack(spacing: 24) {
            if let sequence = sequence {
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

                if let name = firstNoteName {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("First note: \(name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            } else {
                // Empty state
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
    }

    private func orbState(for index: Int) -> NoteOrbView.State {
        // Error state takes priority
        if let errorIdx = errorIndex, errorIdx == index {
            return .error
        }

        // During playback, show neutral state
        if isPlaying {
            return .pending
        }

        guard let awaiting = awaitingIndex else {
            // Sequence completed - all are correct
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

#Preview {
    NoteOrbsContainerView(
        sequence: nil,
        awaitingIndex: nil,
        errorIndex: nil,
        isPlaying: false,
        firstNoteName: nil
    )
}
