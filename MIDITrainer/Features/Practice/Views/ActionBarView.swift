import SwiftUI

struct ActionBarView: View {
    let hasSequence: Bool
    let isPlaying: Bool
    let midiDeviceName: String?
    let isMidiConnected: Bool
    let onAction: () -> Void
    let onSkip: () -> Void
    let onMidiSettingsTap: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // MIDI Status
            Button(action: onMidiSettingsTap) {
                HStack(spacing: 8) {
                    Image(systemName: "pianokeys")
                        .font(.subheadline)

                    if let deviceName = midiDeviceName {
                        Text(deviceName)
                            .font(.subheadline)
                            .lineLimit(1)
                    } else {
                        Text("No MIDI device")
                            .font(.subheadline)
                    }

                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(midiDeviceName != nil ? Color.secondary : Color.orange)
            }
            .buttonStyle(.plain)

            // Main Action Button with Skip
            HStack(spacing: 12) {
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

                // Skip button
                if hasSequence && !isPlaying {
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
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: hasSequence)
            .animation(.easeInOut(duration: 0.2), value: isPlaying)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var buttonTitle: String {
        if isPlaying {
            return "Playing..."
        }
        return hasSequence ? "REPLAY" : "START"
    }

    private var buttonColor: Color {
        if hasSequence {
            return .blue
        } else {
            return .green
        }
    }

    private var statusColor: Color {
        guard midiDeviceName != nil else {
            return .orange
        }
        return isMidiConnected ? .green : .gray
    }
}

#Preview {
    VStack(spacing: 60) {
        ActionBarView(
            hasSequence: false,
            isPlaying: false,
            midiDeviceName: "Roland FP-30X",
            isMidiConnected: true,
            onAction: {},
            onSkip: {},
            onMidiSettingsTap: {}
        )

        ActionBarView(
            hasSequence: true,
            isPlaying: false,
            midiDeviceName: "Roland FP-30X",
            isMidiConnected: true,
            onAction: {},
            onSkip: {},
            onMidiSettingsTap: {}
        )

        ActionBarView(
            hasSequence: true,
            isPlaying: true,
            midiDeviceName: nil,
            isMidiConnected: false,
            onAction: {},
            onSkip: {},
            onMidiSettingsTap: {}
        )
    }
}
