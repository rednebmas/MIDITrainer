import SwiftUI

struct ActionBarView: View {
    @ObservedObject var model: PracticeModel
    let onAction: () -> Void
    let onMidiSettingsTap: () -> Void

    private var hasSequence: Bool { model.currentSequence != nil }
    private var isPlaying: Bool { model.isPlaying }
    private var isShowingAnswer: Bool { model.isShowingAnswer }
    private var midiDeviceName: String? { model.selectedOutputName }

    private var secondaryButtonsDisabled: Bool { !hasSequence || isPlaying }

    var body: some View {
        VStack(spacing: 12) {
            MIDIStatusButton(model: model, onTap: onMidiSettingsTap)

            HStack(spacing: 12) {
                SkipButton(disabled: secondaryButtonsDisabled) { model.skip() }

                if isShowingAnswer {
                    NextButton(disabled: isPlaying) { model.playQuestion() }
                } else {
                    ShowAnswerButton(disabled: secondaryButtonsDisabled) { model.showAnswer() }
                }
            }

            MainActionButton(
                hasSequence: hasSequence,
                isPlaying: isPlaying,
                onAction: onAction
            )
        }
        .animation(.easeInOut(duration: 0.2), value: hasSequence)
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
        .animation(.easeInOut(duration: 0.2), value: isShowingAnswer)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

private struct MIDIStatusButton: View {
    @ObservedObject var model: PracticeModel
    let onTap: () -> Void

    private var statusColor: Color {
        guard model.selectedOutputName != nil else { return .orange }
        return model.isMidiConnected ? .green : .gray
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "pianokeys")
                    .font(.subheadline)

                if model.isScanningMIDI {
                    Text("Scanning...")
                        .font(.subheadline)
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let deviceName = model.selectedOutputName {
                    Text(deviceName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                } else {
                    Text("No MIDI device")
                        .font(.subheadline)
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(model.selectedOutputName != nil ? Color.secondary : Color.orange)
        }
        .buttonStyle(.plain)
    }
}

private struct MainActionButton: View {
    let hasSequence: Bool
    let isPlaying: Bool
    let onAction: () -> Void

    private var buttonTitle: String {
        if isPlaying { return "Playing..." }
        return hasSequence ? "REPLAY" : "START"
    }

    private var buttonColor: Color {
        hasSequence ? .blue : .green
    }

    var body: some View {
        Button(action: onAction) {
            HStack(spacing: 8) {
                if isPlaying {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: hasSequence ? "arrow.counterclockwise" : "play.fill")
                        .font(.headline)
                }

                Text(buttonTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: 280)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(buttonColor)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isPlaying)
        .opacity(isPlaying ? 0.7 : 1)
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
        .animation(.easeInOut(duration: 0.2), value: hasSequence)
    }
}

private struct SkipButton: View {
    let disabled: Bool
    let onSkip: () -> Void

    var body: some View {
        Button(action: onSkip) {
            Image(systemName: "forward.fill")
                .font(.headline)
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.secondary.opacity(0.3))
                )
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

private struct ShowAnswerButton: View {
    let disabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.headline)
                Text("Show Answer")
                    .font(.headline.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.3))
            )
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

private struct NextButton: View {
    let disabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text("NEXT")
                    .font(.headline.weight(.semibold))
                Image(systemName: "arrow.right")
                    .font(.headline)
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.3))
            )
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

