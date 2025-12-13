// This file avoids using RangeSet or array literals for tags or ForEach iterations,
// as these usages are incorrect and may produce build errors.

import Combine
import CoreAudioKit
import CoreMIDI
import SwiftUI

struct PracticeView: View {
    @StateObject private var model: PracticeModel
    @State private var showingBluetoothPicker = false
    @State private var showingMissingOutput = false

    private enum OutputChoice: Hashable {
        case endpoint(MIDIUniqueID)
        case bluetooth
    }

    init(midiService: MIDIService, settingsStore: SettingsStore) {
        _model = StateObject(wrappedValue: PracticeModel(midiService: midiService, settingsStore: settingsStore))
    }

    private var firstNoteName: String? {
        guard let midiNumber = model.currentSequence?.notes.first?.midiNoteNumber,
              let noteName = NoteName(rawValue: Int(midiNumber % 12)) else { return nil }
        return noteName.displayName
    }

    private var dedupedOutputs: [MIDIEndpoint] {
        var seen: Set<String> = []
        return model.availableOutputs.filter { endpoint in
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
                Section("Playback") {
                    HStack {
                        Button(model.currentSequence == nil ? "Start" : "Next Question") {
                            guard model.selectedOutputID != nil || model.availableOutputs.isEmpty == false else {
                                showingMissingOutput = true
                                return
                            }
                            model.playQuestion()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isPlaying)

                        Button("Replay") {
                            model.replay()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.currentSequence == nil || model.isPlaying)
                    }

                    if let name = firstNoteName {
                        Text("First note: \(name)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if model.isPlaying {
                        Text("Playing...")
                            .foregroundStyle(.secondary)
                    } else if let index = model.awaitingNoteIndex {
                        Text("Awaiting note \(index + 1) of \(model.currentSequence?.notes.count ?? 0)")
                            .foregroundStyle(.secondary)
                    }

                    if let sequence = model.currentSequence {
                        progressDots(for: sequence)
                    }
                }

                Section("MIDI") {
                    if dedupedOutputs.isEmpty {
                        Text("No MIDI outputs available")
                            .foregroundStyle(.secondary)
                    }
                    
                    Picker("Destination", selection: outputSelectionBinding) {
                        if dedupedOutputs.isEmpty {
                            Text("None").tag(OutputChoice.bluetooth)
                        }
                        ForEach(dedupedOutputs, id: \.id) { endpoint in
                            Text(endpoint.name).tag(OutputChoice.endpoint(endpoint.id))
                        }
                        Text("Bluetooth MIDI…").tag(OutputChoice.bluetooth)
                    }
                    .pickerStyle(.menu)
                    
                    HStack {
                        Text("Keys down")
                        Circle()
                            .fill(model.heldNotesCount > 0 ? Color.green : Color.gray.opacity(0.4))
                            .frame(width: 12, height: 12)
                        Text("\(model.heldNotesCount)")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                    
                }
            }
            .navigationTitle("Practice")
            .sheet(isPresented: $showingBluetoothPicker, onDismiss: {
                // Refresh endpoints after Bluetooth picker is dismissed
                // to pick up any newly connected devices
                model.refreshEndpoints()
            }) {
                BluetoothMIDIPicker()
            }
            .alert("MIDI output not available", isPresented: $showingMissingOutput) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please select a MIDI destination before playing.")
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

    private var outputSelectionBinding: Binding<OutputChoice> {
        Binding<OutputChoice>(
            get: {
                if let id = model.selectedOutputID {
                    return .endpoint(id)
                }
                return .bluetooth
            },
            set: { choice in
                switch choice {
                case .endpoint(let id):
                    model.selectOutput(id: id)
                case .bluetooth:
                    showingBluetoothPicker = true
                }
            }
        )
    }

    private func progressDots(for sequence: MelodySequence) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(sequence.notes.enumerated()), id: \.offset) { index, _ in
                Circle()
                    .fill(colorForNoteIndex(index))
                    .frame(width: 14, height: 14)
            }
        }
        .padding(.vertical, 4)
    }

    private func colorForNoteIndex(_ index: Int) -> Color {
        guard let awaiting = model.awaitingNoteIndex else {
            return .green
        }
        if index < awaiting {
            return .green
        } else if index == awaiting {
            return .yellow
        } else {
            return .gray.opacity(0.4)
        }
    }
}

struct BluetoothMIDIPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController {
        CABTMIDICentralViewController()
    }

    func updateUIViewController(_ uiViewController: CABTMIDICentralViewController, context: Context) {}
}
