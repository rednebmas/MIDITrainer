import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    private var volumePercentage: Int {
        Int(settingsStore.midiOutputVolume * 100)
    }

    private var chordVolumePercentage: Int {
        Int(settingsStore.chordVolumeRatio * 100)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("MIDI Output Volume")
                        Spacer()
                        Text("\(volumePercentage)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $settingsStore.midiOutputVolume,
                        in: 0...1,
                        step: 0.05
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Chord Volume")
                        Spacer()
                        Text("\(chordVolumePercentage)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: $settingsStore.chordVolumeRatio,
                        in: 0...1,
                        step: 0.05
                    )
                }
            } header: {
                Text("Audio")
            } footer: {
                Text("MIDI Output Volume controls overall volume. Chord Volume is relative to melody notes.")
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AdvancedSettingsView()
            .environmentObject(SettingsStore())
    }
}
