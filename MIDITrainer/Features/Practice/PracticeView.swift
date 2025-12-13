import Combine
import CoreAudioKit
import CoreMIDI
import SwiftUI

struct PracticeView: View {
    @StateObject private var model: PracticeModel
    @State private var showingMIDISettings = false
    @State private var showingBluetoothPicker = false
    @State private var showingMissingOutput = false
    @State private var showingDebug = false

    init(midiService: MIDIService, settingsStore: SettingsStore) {
        _model = StateObject(wrappedValue: PracticeModel(midiService: midiService, settingsStore: settingsStore))
    }

    private var firstNoteName: String? {
        guard let midiNumber = model.currentSequence?.notes.first?.midiNoteNumber,
              let noteName = NoteName(rawValue: Int(midiNumber % 12)) else { return nil }
        return noteName.displayName
    }

    private var isMidiConnected: Bool {
        guard let outputID = model.selectedOutputID else { return false }
        return model.availableOutputs.first(where: { $0.id == outputID })?.isOffline == false
    }

    private func feedbackType(for feedback: SequenceFeedback) -> FeedbackType {
        switch feedback {
        case .perfect: return .perfect
        case .correct: return .correct
        case .tryAgain: return .tryAgain
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Stats Bar
            GameStatsBarView(
                accuracy: model.firstTryAccuracy?.rate,
                accuracyCount: model.firstTryAccuracy?.totalCount ?? 0,
                questionsToday: model.questionsAnsweredToday,
                dailyGoal: model.dailyGoal,
                streak: model.currentStreak
            )
            .padding(.top, 16)

            Spacer()

            // Center Stage - Note Orbs
            ZStack {
                NoteOrbsContainerView(
                    sequence: model.currentSequence,
                    awaitingIndex: model.awaitingNoteIndex,
                    errorIndex: model.errorNoteIndex,
                    isPlaying: model.isPlaying,
                    firstNoteName: firstNoteName
                )

                // Floating Feedback Overlay
                if let feedback = model.latestFeedback {
                    FloatingFeedbackView(
                        type: feedbackType(for: feedback),
                        isVisible: true
                    )
                    .offset(y: -80)
                }
            }

            Spacer()

            // Bottom Action Bar
            ActionBarView(
                hasSequence: model.currentSequence != nil,
                isPlaying: model.isPlaying,
                midiDeviceName: model.selectedOutputName,
                isMidiConnected: isMidiConnected,
                onAction: handleAction,
                onMidiSettingsTap: { showingMIDISettings = true }
            )
            .padding(.bottom, 8)

            // Debug toggle
            Button {
                withAnimation { showingDebug.toggle() }
            } label: {
                HStack {
                    Image(systemName: showingDebug ? "chevron.down" : "chevron.right")
                        .font(.caption)
                    Text("Scheduler Debug")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

            // Debug Section
            if showingDebug {
                SchedulerDebugView(
                    entries: model.schedulerDebugEntries,
                    pendingCount: model.pendingMistakeCount,
                    questionsUntilNextReask: model.questionsUntilNextReask,
                    onClearQueue: { model.clearMistakeQueue() }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showingMIDISettings) {
            MIDISettingsSheet(
                availableOutputs: model.availableOutputs,
                selectedOutputID: model.selectedOutputID,
                onSelectOutput: { id in
                    model.selectOutput(id: id)
                },
                onBluetoothTap: {
                    showingMIDISettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showingBluetoothPicker = true
                    }
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingBluetoothPicker, onDismiss: {
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

    private func handleAction() {
        guard model.selectedOutputID != nil || !model.availableOutputs.isEmpty else {
            showingMissingOutput = true
            return
        }

        if model.currentSequence == nil {
            // Start new session
            model.playQuestion()
        } else {
            // Replay current sequence
            model.replay()
        }
    }
}

// MARK: - Scheduler Debug View

struct SchedulerDebugView: View {
    let entries: [SchedulerDebugEntry]
    let pendingCount: Int
    let questionsUntilNextReask: Int?
    let onClearQueue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with summary
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Re-ask Queue")
                        .font(.subheadline.weight(.medium))
                    if pendingCount > 0 {
                        if let remaining = questionsUntilNextReask, remaining > 0 {
                            Text("Next re-ask in \(remaining) question\(remaining == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else {
                            Text("Re-ask ready now")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    } else {
                        Text("No mistakes queued")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if pendingCount > 0 {
                    Button("Clear All") {
                        onClearQueue()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            // Queued mistakes list
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        MistakeEntryRow(entry: entry, index: index + 1)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

struct MistakeEntryRow: View {
    let entry: SchedulerDebugEntry
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            // Index badge
            Text("#\(index)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 20)
                .background(statusColor.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                // Status
                Text(statusDescription)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)

                // Progress info
                Text(progressDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Visual progress indicator
            if !entry.isDue && !entry.isActive {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 50)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusDescription: String {
        if entry.isActive { return "Now playing" }
        if entry.isDue { return "Ready to play" }
        return "Waiting (\(entry.remainingUntilDue) more)"
    }

    private var progressDescription: String {
        if entry.isActive { return "Testing your recall" }
        if entry.isDue { return "Will be asked next" }
        return "Answered \(entry.questionsSinceQueued) of \(entry.currentClearanceDistance) needed"
    }

    private var progress: Double {
        guard entry.currentClearanceDistance > 0 else { return 0 }
        return Double(entry.questionsSinceQueued) / Double(entry.currentClearanceDistance)
    }

    private var statusColor: Color {
        if entry.isActive { return .green }
        if entry.isDue { return .orange }
        return .blue
    }
}
