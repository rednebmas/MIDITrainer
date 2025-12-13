import Combine
import CoreAudioKit
import CoreMIDI
import SwiftUI

struct PracticeView: View {
    @StateObject private var model: PracticeModel
    @State private var showingBluetoothPicker = false

    init(midiService: MIDIService) {
        _model = StateObject(wrappedValue: PracticeModel(midiService: midiService))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Inputs") {
                    if model.availableInputs.isEmpty {
                        Text("No MIDI inputs detected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.availableInputs) { endpoint in
                            let isConnected = model.connectedInputs.contains(where: { $0.id == endpoint.id })
                            Button {
                                model.toggleInput(id: endpoint.id)
                            } label: {
                                HStack {
                                    Text(endpoint.name)
                                    Spacer()
                                    Label(isConnected ? "Connected" : "Tap to connect", systemImage: isConnected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isConnected ? .green : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        showingBluetoothPicker = true
                    } label: {
                        Label("Bluetooth MIDI…", systemImage: "bolt.horizontal")
                    }
                }

                Section("Output") {
                    if model.availableOutputs.isEmpty {
                        Text("No MIDI outputs available")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Destination", selection: selectedOutputBinding) {
                            ForEach(model.availableOutputs) { endpoint in
                                Text(endpoint.name).tag(Optional(endpoint.id))
                            }
                        }
                        .pickerStyle(.menu)

                        if let selected = model.availableOutputs.first(where: { $0.id == model.selectedOutputID }) {
                            Text("Selected: \(selected.name)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Recent MIDI") {
                    if model.recentEvents.isEmpty {
                        Text("Play a note on your controller to see events.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.recentEvents, id: \.self) { event in
                            Text(event)
                        }
                    }
                }

                Section("Actions") {
                    Button("Send middle C") {
                        model.sendTestNote()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refresh MIDI") {
                        model.refreshEndpoints()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .navigationTitle("Practice")
            .sheet(isPresented: $showingBluetoothPicker) {
                BluetoothMIDIPicker()
            }
        }
    }

    private var selectedOutputBinding: Binding<MIDIUniqueID?> {
        Binding<MIDIUniqueID?>(
            get: { model.selectedOutputID },
            set: { id in
                if let id {
                    model.selectOutput(id: id)
                }
            }
        )
    }
}

struct BluetoothMIDIPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController {
        CABTMIDICentralViewController()
    }

    func updateUIViewController(_ uiViewController: CABTMIDICentralViewController, context: Context) {}
}
