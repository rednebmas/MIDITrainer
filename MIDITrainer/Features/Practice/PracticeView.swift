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
    @State private var showingAccuracyHistory = false

    init(midiService: MIDIService, settingsStore: SettingsStore) {
        _model = StateObject(wrappedValue: PracticeModel(midiService: midiService, settingsStore: settingsStore))
    }

    private var firstNoteName: String? {
        guard let midiNumber = model.currentSequence?.notes.first?.midiNoteNumber,
              let noteName = NoteName(rawValue: Int(midiNumber % 12)) else { return nil }
        return noteName.displayName
    }

    private var isMidiConnected: Bool {
        if model.useOnScreenKeyboard { return true }
        guard let outputID = model.selectedOutputID else { return false }
        return model.availableOutputs.first(where: { $0.id == outputID })?.isOffline == false
    }

    private var keyboardOctaves: [Int] {
        model.settings.allowedOctaves.isEmpty ? [4] : model.settings.allowedOctaves
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
                streak: model.currentStreak,
                onAccuracyTap: { showingAccuracyHistory = true }
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
                    firstNoteName: firstNoteName,
                    sourceName: model.currentSequence?.sourceName
                )

                // Floating Feedback Overlay
                if let feedback = model.latestFeedback {
                    FloatingFeedbackView(
                        type: feedbackType(for: feedback),
                        isVisible: true
                    )
                    .offset(y: -120)
                }
            }

            Spacer()

            // On-Screen Keyboard (when enabled)
            if model.useOnScreenKeyboard {
                OnScreenKeyboardView(
                    octaves: keyboardOctaves,
                    onNoteOn: { note in model.injectNoteOn(note) },
                    onNoteOff: { note in model.injectNoteOff(note) }
                )
                .padding(.bottom, 8)
            }

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
                useOnScreenKeyboard: model.useOnScreenKeyboard,
                onSelectOutput: { id in
                    model.selectOutput(id: id)
                },
                onToggleOnScreenKeyboard: { enabled in
                    model.setUseOnScreenKeyboard(enabled)
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
        .sheet(isPresented: $showingAccuracyHistory) {
            AccuracyHistorySheet(
                entries: model.sequenceHistory,
                keyRoot: model.settings.key.root
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func handleAction() {
        // Allow starting if using on-screen keyboard or MIDI output is available
        guard model.useOnScreenKeyboard || model.selectedOutputID != nil || !model.availableOutputs.isEmpty else {
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
