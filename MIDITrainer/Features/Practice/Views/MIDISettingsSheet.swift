import CoreAudioKit
import CoreMIDI
import SwiftUI

struct MIDISettingsSheet: View {
    let availableOutputs: [MIDIEndpoint]
    let selectedOutputID: MIDIUniqueID?
    let onSelectOutput: (MIDIUniqueID) -> Void
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

                                if endpoint.id == selectedOutputID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("MIDI Outputs")
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
            .navigationTitle("MIDI Settings")
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
        onSelectOutput: { _ in },
        onBluetoothTap: {}
    )
}
