import CoreMIDI
import Foundation
import Combine

final class SettingsStore: ObservableObject {
    @Published var settings: PracticeSettingsSnapshot {
        didSet { save(settings) }
    }
    @Published var feedback: FeedbackSettings {
        didSet { saveFeedback(feedback) }
    }
    @Published var replayHotkeyEnabled: Bool {
        didSet { defaults.set(replayHotkeyEnabled, forKey: replayHotkeyKey) }
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

    private let defaults: UserDefaults
    private let key = "com.sambender.miditrainer.settings"
    private let feedbackKey = "com.sambender.miditrainer.feedback"
    private let replayHotkeyKey = "com.sambender.miditrainer.replayHotkeyEnabled"
    private let schedulerModeKey = "com.sambender.miditrainer.schedulerMode"
    private let lastOutputIDKey = "com.sambender.miditrainer.lastOutputID"
    private let lastOutputNameKey = "com.sambender.miditrainer.lastOutputName"
    private let dailyGoalKey = "com.sambender.miditrainer.dailyGoal"
    private let questionsAnsweredTodayKey = "com.sambender.miditrainer.questionsAnsweredToday"
    private let lastPracticeDateKey = "com.sambender.miditrainer.lastPracticeDate"
    private let currentStreakKey = "com.sambender.miditrainer.currentStreak"
    private let useOnScreenKeyboardKey = "com.sambender.miditrainer.useOnScreenKeyboard"

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = SettingsStore.load(defaults: defaults, key: key) ?? PracticeSettingsSnapshot()
        self.feedback = SettingsStore.loadFeedback(defaults: defaults, key: feedbackKey) ?? FeedbackSettings()
        self.replayHotkeyEnabled = defaults.object(forKey: replayHotkeyKey) as? Bool ?? false
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
        questionsAnsweredToday += 1
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

    func updateFeedback(_ newFeedback: FeedbackSettings) {
        feedback = newFeedback
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

    private func saveFeedback(_ settings: FeedbackSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: feedbackKey)
        }
    }

    private static func loadFeedback(defaults: UserDefaults, key: String) -> FeedbackSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FeedbackSettings.self, from: data)
    }
}
