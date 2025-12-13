import CoreAudioKit
import CoreMIDI
import SwiftUI

struct MIDISettingsSheet: View {
    let availableOutputs: [MIDIEndpoint]
    let selectedOutputID: MIDIUniqueID?
    let useOnScreenKeyboard: Bool
    let onSelectOutput: (MIDIUniqueID) -> Void
    let onToggleOnScreenKeyboard: (Bool) -> Void
    let onBluetoothTap: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var dedupedOutputs: [MIDIEndpoint] {
        var seen: Set<String> = []
        return availableOutputs.filter { endpoint in
            if seen.contains(endpoint.name) {
                return false
            } else {
                seen.insert(endpoint.name)
                return true
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if dedupedOutputs.isEmpty {
                        Text("No MIDI outputs available")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(dedupedOutputs, id: \.id) { endpoint in
                        Button {
                            onToggleOnScreenKeyboard(false)
                            onSelectOutput(endpoint.id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(endpoint.name)
                                        .foregroundStyle(.primary)
                                    if endpoint.isOffline {
                                        Text("Offline")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }

                                Spacer()

                                if !useOnScreenKeyboard && endpoint.id == selectedOutputID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("MIDI Devices")
                } footer: {
                    Text("Connect a MIDI keyboard for the best experience")
                }

                Section {
                    Button {
                        onToggleOnScreenKeyboard(true)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "pianokeys")
                            Text("On-Screen Keyboard")
                                .foregroundStyle(.primary)

                            Spacer()

                            if useOnScreenKeyboard {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Virtual Input")
                } footer: {
                    Text("Use when you don't have a MIDI device connected")
                }

                Section {
                    Button {
                        onBluetoothTap()
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Connect Bluetooth MIDI...")
                        }
                    }
                }
            }
            .navigationTitle("Input Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct BluetoothMIDIPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController {
        CABTMIDICentralViewController()
    }

    func updateUIViewController(_ uiViewController: CABTMIDICentralViewController, context: Context) {}
}

#Preview {
    MIDISettingsSheet(
        availableOutputs: [],
        selectedOutputID: nil,
        useOnScreenKeyboard: false,
        onSelectOutput: { _ in },
        onToggleOnScreenKeyboard: { _ in },
        onBluetoothTap: {}
    )
}
