import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var draft: PracticeSettingsSnapshot = PracticeSettingsSnapshot()
    @State private var feedback: FeedbackSettings = FeedbackSettings()

    private let allOctaves = Array(1...7)

    var body: some View {
        NavigationStack {
            Form {
                Section("Scheduling") {
                    Picker("Question Mode", selection: $settingsStore.schedulerMode) {
                        ForEach(SchedulerMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Text(settingsStore.schedulerMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if settingsStore.schedulerMode == .weaknessFocused {
                        Toggle("Limit to current settings", isOn: $settingsStore.weaknessMatchExactSettings)

                        Text(settingsStore.weaknessMatchExactSettings
                            ? "Only shows weaknesses matching current BPM, length, degrees, and octaves"
                            : "Shows all weaknesses for this key and scale")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        WeaknessQueueDebugView(settings: draft, matchExactSettings: settingsStore.weaknessMatchExactSettings)
                    }
                }

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
                    Picker("Source", selection: $draft.melodySourceType) {
                        ForEach(MelodySourceType.allCases, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(lengthRangeLabel)
                        HStack {
                            Text("\(draft.melodyLengthMin)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Slider(
                                value: Binding(
                                    get: { Double(draft.melodyLengthMin) },
                                    set: { draft.melodyLengthMin = Int($0) }
                                ),
                                in: 1...12,
                                step: 1
                            )
                            Slider(
                                value: Binding(
                                    get: { Double(draft.melodyLengthMax) },
                                    set: { draft.melodyLengthMax = max(draft.melodyLengthMin, Int($0)) }
                                ),
                                in: 1...12,
                                step: 1
                            )
                            Text("\(draft.melodyLengthMax)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                        }
                    }

                    if let description = melodySourceDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Stepper("BPM: \(draft.bpm)", value: $draft.bpm, in: 40...200)
                }

                // Show chord accompaniment settings when using a source with chords
                if draft.melodySourceType.hasChords {
                    Section("Chord Accompaniment") {
                        Toggle("Play chords", isOn: $settingsStore.chordAccompanimentEnabled)
                        Toggle("Show chord symbols", isOn: $settingsStore.showChordSymbols)

                        if settingsStore.chordAccompanimentEnabled {
                            Toggle("Loop during input", isOn: $settingsStore.chordLoopDuringInput)

                            Text(settingsStore.chordLoopDuringInput
                                ? "Chords will loop while you play back the melody"
                                : "Chords only play during initial melody playback")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Picker("Voicing", selection: $settingsStore.chordVoicingStyle) {
                                ForEach(ChordVoicingStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                        }
                    }
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

                Section {
                    NavigationLink {
                        AdvancedSettingsView()
                    } label: {
                        Text("Advanced")
                    }
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
            bpm: draft.bpm,
            melodySourceType: draft.melodySourceType,
            melodyLengthMin: draft.melodyLengthMin,
            melodyLengthMax: draft.melodyLengthMax
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
            bpm: draft.bpm,
            melodySourceType: draft.melodySourceType,
            melodyLengthMin: draft.melodyLengthMin,
            melodyLengthMax: draft.melodyLengthMax
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
            bpm: draft.bpm,
            melodySourceType: draft.melodySourceType,
            melodyLengthMin: draft.melodyLengthMin,
            melodyLengthMax: draft.melodyLengthMax
        )
    }

    private var lengthRangeLabel: String {
        if draft.melodyLengthMin == draft.melodyLengthMax {
            return "Length: \(draft.melodyLengthMin) notes"
        } else {
            return "Length: \(draft.melodyLengthMin)-\(draft.melodyLengthMax) notes"
        }
    }

    private var melodySourceDescription: String? {
        switch draft.melodySourceType {
        case .random:
            return nil
        case .pop909:
            return "\(matchingMelodyCount) matching melodies from 909 pop songs from the POP909 dataset"
        case .billboard:
            return "\(matchingMelodyCount) matching melodies from Billboard Year-End #1-5 hits, 1950-2022"
        case .weimarJazz:
            return "\(matchingMelodyCount) matching melodies from 456 jazz solo transcriptions (Weimar Jazz Database)"
        }
    }

    private var matchingMelodyCount: Int {
        guard draft.melodySourceType.isRealMelody else { return 0 }

        let scale = Scale(key: draft.key, type: draft.scaleType)
        let allowedDegrees = ScaleDegree.allCases.filter { !draft.excludedDegrees.contains($0) }
        let lengthRange = draft.melodyLengthMin...draft.melodyLengthMax

        switch draft.melodySourceType {
        case .weimarJazz:
            let source = AccompaniedMelodySource(library: MelodyLibrary.weimarJazz)
            return source.countMatchingPhrases(
                lengthRange: lengthRange,
                scale: scale,
                allowedDegrees: allowedDegrees,
                allowedOctaves: draft.allowedOctaves
            )
        case .pop909, .billboard:
            let library = MelodyLibrary.library(for: draft.melodySourceType)
            let source = RealMelodySource(library: library)
            return source.countMatchingPhrases(
                lengthRange: lengthRange,
                scale: scale,
                allowedDegrees: allowedDegrees,
                allowedOctaves: draft.allowedOctaves
            )
        case .random:
            return 0
        }
    }

    private func label(for mode: FeedbackMode) -> String {
        switch mode {
        case .none: return "Off"
        case .rootNote: return "Root Note"
        case .rootTriad: return "Root Triad"
        }
    }
}
