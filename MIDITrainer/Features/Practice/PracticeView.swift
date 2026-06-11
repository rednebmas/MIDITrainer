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
    @State private var bluetoothPickerBaselineEndpoints: Set<MIDIUniqueID> = []

    init(midiService: MIDIService, settingsStore: SettingsStore) {
        _model = StateObject(wrappedValue: PracticeModel(midiService: midiService, settingsStore: settingsStore))
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
        ZStack {
            DynamicBackgroundView(model: model)
                .ignoresSafeArea()

            mainContent

            StreakMilestoneBannerView(model: model)
            DailyGoalCelebrationView(model: model)
        }
        .sheet(isPresented: $showingMIDISettings) {
            MIDISettingsSheet(
                model: model,
                onBluetoothTap: {
                    showingMIDISettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        bluetoothPickerBaselineEndpoints = onlineEndpointIDs()
                        showingBluetoothPicker = true
                    }
                }
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingBluetoothPicker, onDismiss: {
            print("[MIDI] BluetoothPicker onDismiss called - refreshing endpoints")
            model.refreshEndpoints()
        }) {
            BluetoothMIDIPicker()
        }
        .onChange(of: model.availableOutputs) { _, _ in dismissBluetoothPickerIfNewEndpoint() }
        .onChange(of: model.availableInputs) { _, _ in dismissBluetoothPickerIfNewEndpoint() }
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
        #if DEBUG
        .sheet(isPresented: $showingDebug) {
            SchedulerDebugSheet(model: model)
                .presentationDetents([.medium, .large])
        }
        #endif
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Top Stats Bar
            GameStatsBarView(
                model: model,
                onAccuracyTap: { showingAccuracyHistory = true }
            )
            .padding(.top, 16)

            Spacer()

            // Center Stage - Note Orbs
            ZStack {
                NoteOrbsContainerView(model: model)

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
                model: model,
                onAction: handleAction,
                onMidiSettingsTap: { showingMIDISettings = true }
            )
            .padding(.bottom, 8)

            #if DEBUG
            Button {
                showingDebug = true
            } label: {
                Text("Debug")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
            #endif
        }
    }

    private func onlineEndpointIDs() -> Set<MIDIUniqueID> {
        let outputIDs = model.availableOutputs.filter { !$0.isOffline }.map(\.id)
        let inputIDs = model.availableInputs.filter { !$0.isOffline }.map(\.id)
        return Set(outputIDs).union(inputIDs)
    }

    private func dismissBluetoothPickerIfNewEndpoint() {
        guard showingBluetoothPicker else { return }
        let newlyOnline = onlineEndpointIDs().subtracting(bluetoothPickerBaselineEndpoints)
        guard !newlyOnline.isEmpty else { return }
        print("[MIDI] BluetoothPicker auto-dismissing — new endpoint(s): \(newlyOnline)")
        showingBluetoothPicker = false
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
