import Foundation
import Combine

final class SettingsStore: ObservableObject {
    @Published var settings: PracticeSettingsSnapshot {
        didSet {
            save(settings)
        }
    }

    private let defaults: UserDefaults
    private let key = "com.sambender.miditrainer.settings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = SettingsStore.load(defaults: defaults, key: key) ?? PracticeSettingsSnapshot()
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
}
