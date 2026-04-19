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

            Section {
                Picker("Melody Channel", selection: $settingsStore.melodyMIDIChannel) {
                    ForEach(0..<16, id: \.self) { channel in
                        Text("\(channel + 1)").tag(channel)
                    }
                }

                Picker("Chord Channel", selection: $settingsStore.chordMIDIChannel) {
                    ForEach(0..<16, id: \.self) { channel in
                        Text("\(channel + 1)").tag(channel)
                    }
                }
            } header: {
                Text("MIDI Channels")
            } footer: {
                Text("Set different channels to route melody and chords to separate sounds on your synthesizer.")
            }

            Section {
                Stepper("Clearance: \(settingsStore.spacedMistakeClearance)", value: $settingsStore.spacedMistakeClearance, in: 1...20)
                Stepper("Min passes to clear: \(settingsStore.spacedMistakeMinPasses)", value: $settingsStore.spacedMistakeMinPasses, in: 1...10)
            } header: {
                Text("Spaced Repetition")
            } footer: {
                Text("Clearance sets how many fresh questions between re-asks. Min passes is the minimum number of successful re-asks required to clear a mistake — a card with more failures needs at least as many passes as failures.")
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
