import CoreMIDI
import Foundation
import Combine

struct DeviceSettings: Codable, Equatable {
    var playSamplesForMIDIInput: Bool = false
}

final class SettingsStore: ObservableObject {
    @Published var settings: PracticeSettingsSnapshot {
        didSet { save(settings) }
    }
    @Published var replayHotkeyNote: UInt8? {
        didSet {
            if let note = replayHotkeyNote {
                defaults.set(Int(note), forKey: replayHotkeyNoteKey)
            } else {
                defaults.removeObject(forKey: replayHotkeyNoteKey)
            }
        }
    }
    @Published var schedulerMode: SchedulerMode {
        didSet { defaults.set(schedulerMode.rawValue, forKey: schedulerModeKey) }
    }
    /// The unique ID of the last selected MIDI output device
    @Published var lastSelectedOutputID: MIDIUniqueID? {
        didSet {
            if let id = lastSelectedOutputID {
                defaults.set(Int(id), forKey: lastOutputIDKey)
            } else {
                defaults.removeObject(forKey: lastOutputIDKey)
            }
        }
    }
    /// The display name of the last selected MIDI output device (for matching if ID changes)
    @Published var lastSelectedOutputName: String? {
        didSet {
            defaults.set(lastSelectedOutputName, forKey: lastOutputNameKey)
        }
    }
    /// Daily practice goal (number of questions)
    @Published var dailyGoal: Int {
        didSet { defaults.set(dailyGoal, forKey: dailyGoalKey) }
    }
    /// Number of questions answered today
    @Published var questionsAnsweredToday: Int {
        didSet {
            defaults.set(questionsAnsweredToday, forKey: questionsAnsweredTodayKey)
            defaults.set(todayDateString, forKey: lastPracticeDateKey)
        }
    }
    /// Current streak of perfect sequences
    @Published var currentStreak: Int {
        didSet { defaults.set(currentStreak, forKey: currentStreakKey) }
    }
    /// Whether to use the on-screen keyboard instead of MIDI input
    @Published var useOnScreenKeyboard: Bool {
        didSet { defaults.set(useOnScreenKeyboard, forKey: useOnScreenKeyboardKey) }
    }
    /// MIDI output volume (0.0 to 1.0)
    @Published var midiOutputVolume: Double {
        didSet { defaults.set(midiOutputVolume, forKey: midiOutputVolumeKey) }
    }
    /// Whether weakness tracking should match exact settings (BPM, length, etc.) or just key/scale
    @Published var weaknessMatchExactSettings: Bool {
        didSet { defaults.set(weaknessMatchExactSettings, forKey: weaknessMatchExactSettingsKey) }
    }
    /// Whether to play chord accompaniment with jazz melodies
    @Published var chordAccompanimentEnabled: Bool {
        didSet { defaults.set(chordAccompanimentEnabled, forKey: chordAccompanimentEnabledKey) }
    }
    /// Whether chords should loop during user input phase (vs only playing during initial playback)
    @Published var chordLoopDuringInput: Bool {
        didSet { defaults.set(chordLoopDuringInput, forKey: chordLoopDuringInputKey) }
    }
    /// Chord voicing style
    @Published var chordVoicingStyle: ChordVoicingStyle {
        didSet { defaults.set(chordVoicingStyle.rawValue, forKey: chordVoicingStyleKey) }
    }
    /// Whether to show chord symbols on the practice screen
    @Published var showChordSymbols: Bool {
        didSet { defaults.set(showChordSymbols, forKey: showChordSymbolsKey) }
    }
    /// Chord volume as a ratio of melody volume (0.0 to 1.0)
    @Published var chordVolumeRatio: Double {
        didSet { defaults.set(chordVolumeRatio, forKey: chordVolumeRatioKey) }
    }
    @Published var melodyMIDIChannel: Int {
        didSet { defaults.set(melodyMIDIChannel, forKey: melodyMIDIChannelKey) }
    }
    @Published var chordMIDIChannel: Int {
        didSet { defaults.set(chordMIDIChannel, forKey: chordMIDIChannelKey) }
    }
    /// Whether to weight random melody generation toward intervals with high error rates
    @Published var weightIntervalsByErrorRate: Bool {
        didSet { defaults.set(weightIntervalsByErrorRate, forKey: weightIntervalsByErrorRateKey) }
    }
    /// Whether octave matters when matching notes (when false, only pitch class matters)
    @Published var octaveMatters: Bool {
        didSet { defaults.set(octaveMatters, forKey: octaveMattersKey) }
    }
    /// Whether to show note orbs indicating melody progress (when false, shows status text only)
    @Published var showNoteOrbs: Bool {
        didSet { defaults.set(showNoteOrbs, forKey: showNoteOrbsKey) }
    }
    /// Number of questions between mistake re-asks in spaced repetition mode
    @Published var spacedMistakeClearance: Int {
        didSet { defaults.set(spacedMistakeClearance, forKey: spacedMistakeClearanceKey) }
    }
    /// Minimum successful passes required to clear a mistake (floor on clearance multiplier)
    @Published var spacedMistakeMinPasses: Int {
        didSet { defaults.set(spacedMistakeMinPasses, forKey: spacedMistakeMinPassesKey) }
    }
    /// First-guess accuracy the adaptive mode steers toward (0.65–0.95)
    @Published var adaptiveTargetAccuracy: Double {
        didSet { defaults.set(adaptiveTargetAccuracy, forKey: adaptiveTargetAccuracyKey) }
    }
    /// Whether adaptive mode drills a failed melody's fragments immediately after the failure
    @Published var adaptiveImmediateDrills: Bool {
        didSet { defaults.set(adaptiveImmediateDrills, forKey: adaptiveImmediateDrillsKey) }
    }

    private var deviceSettingsCache: [String: DeviceSettings] = [:]

    private let defaults: UserDefaults
    private let key = "com.sambender.miditrainer.settings"
    private let replayHotkeyNoteKey = "com.sambender.miditrainer.replayHotkeyNote"
    private let schedulerModeKey = "com.sambender.miditrainer.schedulerMode"
    private let lastOutputIDKey = "com.sambender.miditrainer.lastOutputID"
    private let lastOutputNameKey = "com.sambender.miditrainer.lastOutputName"
    private let dailyGoalKey = "com.sambender.miditrainer.dailyGoal"
    private let questionsAnsweredTodayKey = "com.sambender.miditrainer.questionsAnsweredToday"
    private let lastPracticeDateKey = "com.sambender.miditrainer.lastPracticeDate"
    private let currentStreakKey = "com.sambender.miditrainer.currentStreak"
    private let useOnScreenKeyboardKey = "com.sambender.miditrainer.useOnScreenKeyboard"
    private let midiOutputVolumeKey = "com.sambender.miditrainer.midiOutputVolume"
    private let weaknessMatchExactSettingsKey = "com.sambender.miditrainer.weaknessMatchExactSettings"
    private let chordAccompanimentEnabledKey = "com.sambender.miditrainer.chordAccompanimentEnabled"
    private let chordLoopDuringInputKey = "com.sambender.miditrainer.chordLoopDuringInput"
    private let chordVoicingStyleKey = "com.sambender.miditrainer.chordVoicingStyle"
    private let showChordSymbolsKey = "com.sambender.miditrainer.showChordSymbols"
    private let chordVolumeRatioKey = "com.sambender.miditrainer.chordVolumeRatio"
    private let melodyMIDIChannelKey = "com.sambender.miditrainer.melodyMIDIChannel"
    private let chordMIDIChannelKey = "com.sambender.miditrainer.chordMIDIChannel"
    private let weightIntervalsByErrorRateKey = "com.sambender.miditrainer.weightIntervalsByErrorRate"
    private let octaveMattersKey = "com.sambender.miditrainer.octaveMatters"
    private let showNoteOrbsKey = "com.sambender.miditrainer.showNoteOrbs"
    private let spacedMistakeClearanceKey = "com.sambender.miditrainer.spacedMistakeClearance"
    private let spacedMistakeMinPassesKey = "com.sambender.miditrainer.spacedMistakeMinPasses"
    private let adaptiveTargetAccuracyKey = "com.sambender.miditrainer.adaptiveTargetAccuracy"
    private let adaptiveImmediateDrillsKey = "com.sambender.miditrainer.adaptiveImmediateDrills"
    private let deviceSettingsKey = "com.sambender.miditrainer.deviceSettings"

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = SettingsStore.load(defaults: defaults, key: key) ?? PracticeSettingsSnapshot()
        if let storedNote = defaults.object(forKey: replayHotkeyNoteKey) as? Int {
            self.replayHotkeyNote = UInt8(storedNote)
        } else {
            self.replayHotkeyNote = nil
        }
        if let modeString = defaults.string(forKey: schedulerModeKey),
           let mode = SchedulerMode(rawValue: modeString) {
            self.schedulerMode = mode
        } else {
            self.schedulerMode = .spacedMistakes
        }
        if let storedID = defaults.object(forKey: lastOutputIDKey) as? Int {
            self.lastSelectedOutputID = MIDIUniqueID(storedID)
        } else {
            self.lastSelectedOutputID = nil
        }
        self.lastSelectedOutputName = defaults.string(forKey: lastOutputNameKey)
        self.dailyGoal = defaults.object(forKey: dailyGoalKey) as? Int ?? 30
        self.currentStreak = defaults.object(forKey: currentStreakKey) as? Int ?? 0
        self.useOnScreenKeyboard = defaults.object(forKey: useOnScreenKeyboardKey) as? Bool ?? false
        self.midiOutputVolume = defaults.object(forKey: midiOutputVolumeKey) as? Double ?? 0.5
        self.weaknessMatchExactSettings = defaults.object(forKey: weaknessMatchExactSettingsKey) as? Bool ?? false
        self.chordAccompanimentEnabled = defaults.object(forKey: chordAccompanimentEnabledKey) as? Bool ?? true
        self.chordLoopDuringInput = defaults.object(forKey: chordLoopDuringInputKey) as? Bool ?? false
        if let styleString = defaults.string(forKey: chordVoicingStyleKey),
           let style = ChordVoicingStyle(rawValue: styleString) {
            self.chordVoicingStyle = style
        } else {
            self.chordVoicingStyle = .shell
        }
        self.showChordSymbols = defaults.object(forKey: showChordSymbolsKey) as? Bool ?? true
        self.chordVolumeRatio = defaults.object(forKey: chordVolumeRatioKey) as? Double ?? 0.5
        self.melodyMIDIChannel = defaults.object(forKey: melodyMIDIChannelKey) as? Int ?? 0
        self.chordMIDIChannel = defaults.object(forKey: chordMIDIChannelKey) as? Int ?? 0
        self.weightIntervalsByErrorRate = defaults.object(forKey: weightIntervalsByErrorRateKey) as? Bool ?? false
        self.octaveMatters = defaults.object(forKey: octaveMattersKey) as? Bool ?? true
        self.showNoteOrbs = defaults.object(forKey: showNoteOrbsKey) as? Bool ?? true
        self.spacedMistakeClearance = defaults.object(forKey: spacedMistakeClearanceKey) as? Int ?? 3
        self.spacedMistakeMinPasses = defaults.object(forKey: spacedMistakeMinPassesKey) as? Int ?? 3
        self.adaptiveTargetAccuracy = defaults.object(forKey: adaptiveTargetAccuracyKey) as? Double ?? 0.70
        self.adaptiveImmediateDrills = defaults.object(forKey: adaptiveImmediateDrillsKey) as? Bool ?? false

        if let data = defaults.data(forKey: deviceSettingsKey),
           let decoded = try? JSONDecoder().decode([String: DeviceSettings].self, from: data) {
            self.deviceSettingsCache = decoded
        }

        // Check if it's a new day and reset daily count if needed
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let lastDate = defaults.string(forKey: lastPracticeDateKey)

        if lastDate == today {
            self.questionsAnsweredToday = defaults.object(forKey: questionsAnsweredTodayKey) as? Int ?? 0
        } else {
            self.questionsAnsweredToday = 0
        }
    }

    func incrementQuestionsAnswered() {
        checkForDayRollover()
        questionsAnsweredToday += 1
    }

    /// Checks if the day has changed since last practice and resets daily stats if so.
    /// Call this when the app returns to foreground.
    func checkForDayRollover() {
        let lastDate = defaults.string(forKey: lastPracticeDateKey)
        if lastDate != todayDateString {
            questionsAnsweredToday = 0
        }
    }

    func incrementStreak() {
        currentStreak += 1
    }

    func resetStreak() {
        currentStreak = 0
    }

    func resetDailyStats() {
        questionsAnsweredToday = 0
        currentStreak = 0
    }

    func update(_ newSettings: PracticeSettingsSnapshot) {
        settings = newSettings
    }

    private func save(_ settings: PracticeSettingsSnapshot) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load(defaults: UserDefaults, key: String) -> PracticeSettingsSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PracticeSettingsSnapshot.self, from: data)
    }

    func deviceSettings(for deviceName: String) -> DeviceSettings {
        deviceSettingsCache[deviceName] ?? DeviceSettings()
    }

    func setDeviceSettings(_ settings: DeviceSettings, for deviceName: String) {
        deviceSettingsCache[deviceName] = settings
        if let data = try? JSONEncoder().encode(deviceSettingsCache) {
            defaults.set(data, forKey: deviceSettingsKey)
        }
    }
}
