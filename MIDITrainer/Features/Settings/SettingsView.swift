import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var draft: PracticeSettingsSnapshot = PracticeSettingsSnapshot()
    @State private var feedback: FeedbackSettings = FeedbackSettings()

    private let allOctaves = Array(1...7)

    var body: some View {
        NavigationStack {
            Form {
                Section("Key & Scale") {
                    Picker("Key", selection: Binding(get: { draft.key.root }, set: { draft = updateKey($0) })) {
                        ForEach(NoteName.allCases, id: \.self) { name in
                            Text(name.displayName).tag(name)
                        }
                    }

                    Picker("Scale", selection: $draft.scaleType) {
                        ForEach(ScaleType.allCases, id: \.self) { scale in
                            Text(scale.storageKey.capitalized).tag(scale)
                        }
                    }
                }

                Section("Melody") {
                    Stepper("Length: \(draft.melodyLength) notes", value: $draft.melodyLength, in: 1...16)
                    Stepper("BPM: \(draft.bpm)", value: $draft.bpm, in: 40...200)
                }

                Section("Octaves") {
                    ForEach(allOctaves, id: \.self) { octave in
                        Toggle("Octave \(octave)", isOn: Binding(
                            get: { draft.allowedOctaves.contains(octave) },
                            set: { isOn in
                                draft = updateOctave(octave, isOn: isOn)
                            }
                        ))
                    }
                }

                Section("Excluded degrees") {
                    ForEach(ScaleDegree.allCases, id: \.self) { degree in
                        Toggle("Degree \(degree.rawValue)", isOn: Binding(
                            get: { draft.excludedDegrees.contains(degree) },
                            set: { isOn in
                                draft = updateExcluded(degree, isOn: isOn)
                            }
                        ))
                    }
                }

                Section("Feedback") {
                    Picker("Mode", selection: $feedback.mode) {
                        ForEach(FeedbackMode.allCases, id: \.self) { mode in
                            Text(label(for: mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Replay on lowest key (A0)", isOn: $settingsStore.replayHotkeyEnabled)
                }

                Section("Scheduling") {
                    Picker("Question Mode", selection: $settingsStore.schedulerMode) {
                        ForEach(SchedulerMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text(settingsStore.schedulerMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            }
            .navigationTitle("Settings")
            .onAppear {
                draft = settingsStore.settings
                feedback = settingsStore.feedback
            }
            .onChange(of: settingsStore.settings) { newValue in
                draft = newValue
            }
            .onDisappear {
                settingsStore.update(draft)
                settingsStore.updateFeedback(feedback)
            }
        }
    }

    private func updateKey(_ note: NoteName) -> PracticeSettingsSnapshot {
        PracticeSettingsSnapshot(
            key: Key(root: note),
            scaleType: draft.scaleType,
            excludedDegrees: draft.excludedDegrees,
            allowedOctaves: draft.allowedOctaves,
            melodyLength: draft.melodyLength,
            bpm: draft.bpm
        )
    }

    private func updateOctave(_ octave: Int, isOn: Bool) -> PracticeSettingsSnapshot {
        var octaves = Set(draft.allowedOctaves)
        if isOn {
            octaves.insert(octave)
        } else {
            octaves.remove(octave)
        }
        let sorted = octaves.sorted()
        return PracticeSettingsSnapshot(
            key: draft.key,
            scaleType: draft.scaleType,
            excludedDegrees: draft.excludedDegrees,
            allowedOctaves: sorted.isEmpty ? draft.allowedOctaves : sorted,
            melodyLength: draft.melodyLength,
            bpm: draft.bpm
        )
    }

    private func updateExcluded(_ degree: ScaleDegree, isOn: Bool) -> PracticeSettingsSnapshot {
        var excluded = draft.excludedDegrees
        if isOn {
            excluded.insert(degree)
        } else {
            excluded.remove(degree)
        }
        return PracticeSettingsSnapshot(
            key: draft.key,
            scaleType: draft.scaleType,
            excludedDegrees: excluded,
            allowedOctaves: draft.allowedOctaves,
            melodyLength: draft.melodyLength,
            bpm: draft.bpm
        )
    }

    private func label(for mode: FeedbackMode) -> String {
        switch mode {
        case .none: return "Off"
        case .rootNote: return "Root Note"
        case .rootTriad: return "Root Triad"
        }
    }
}
