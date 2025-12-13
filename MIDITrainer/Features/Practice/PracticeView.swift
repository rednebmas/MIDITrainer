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

                        Spacer()
                        if model.isPlaying {
                            Text(model.isReplaying ? "Replaying…" : "Playing…")
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        }
                    }

                    if let name = firstNoteName {
                        HStack(spacing: 4) {
                            Text("First note:")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(name)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                        }
                    }

                    firstTryRow()

                    if let sequence = model.currentSequence {
                        progressDots(for: sequence)
                    }
                    
                    if model.pendingMistakeCount > 0 {
                        HStack {
                            if let remaining = model.questionsUntilNextReask, remaining > 0 {
                                Text("Re-ask in \(remaining)")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Re-ask pending")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            Text("\(model.pendingMistakeCount) queued")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Clear") {
                                model.clearMistakeQueue()
                            }
                            .font(.footnote)
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    if !model.schedulerDebugEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Scheduler debug")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            
                            ForEach(model.schedulerDebugEntries) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Seed \(entry.seed)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(schedulerStatusText(for: entry))
                                            .font(.caption2)
                                            .foregroundStyle(schedulerStatusColor(for: entry))
                                    }
                                    
                                    Text("Spacing \(entry.questionsSinceQueued)/\(entry.currentClearanceDistance) • Min \(entry.minimumClearanceDistance) • Remaining \(entry.remainingUntilDue)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 4)
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

    @ViewBuilder
    private func firstTryRow() -> some View {
        if let accuracy = model.firstTryAccuracy {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("First-try accuracy")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Last \(accuracy.totalCount) sequence\(accuracy.totalCount == 1 ? "" : "s") (current settings)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(accuracy.rate, format: .percent.precision(.fractionLength(0)))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(accuracy.rate >= 0.8 ? .green : .primary)
            }
        } else {
            HStack {
                Text("First-try accuracy")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("No data yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
        if let errorIndex = model.errorNoteIndex, errorIndex == index {
            return .red
        }
        // While playback is running, show a neutral state.
        if model.isPlaying {
            return .gray.opacity(0.4)
        }
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
    
    private func schedulerStatusText(for entry: SchedulerDebugEntry) -> String {
        if entry.isActive { return "Playing" }
        if entry.isDue { return "Due" }
        return "Waiting"
    }
    
    private func schedulerStatusColor(for entry: SchedulerDebugEntry) -> Color {
        if entry.isActive { return .green }
        if entry.isDue { return .orange }
        return .secondary
    }
}

struct BluetoothMIDIPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CABTMIDICentralViewController {
        CABTMIDICentralViewController()
    }

    func updateUIViewController(_ uiViewController: CABTMIDICentralViewController, context: Context) {}
}
