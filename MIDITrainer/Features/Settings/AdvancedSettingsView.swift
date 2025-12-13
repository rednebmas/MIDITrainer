import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    private var volumePercentage: Int {
        Int(settingsStore.midiOutputVolume * 100)
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
            } header: {
                Text("Audio")
            } footer: {
                Text("Controls the volume of MIDI notes sent to your instrument and the on-screen keyboard samples.")
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
