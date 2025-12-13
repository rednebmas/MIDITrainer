import Combine
import Foundation

final class StatsModel: ObservableObject {
    enum Scope: String, CaseIterable {
        case allKeys = "All Keys"
        case currentKey = "Current Key"
    }

    @Published var degreeBuckets: [StatBucket] = []
    @Published var intervalBuckets: [StatBucket] = []
    @Published var noteIndexBuckets: [StatBucket] = []
    @Published var scope: Scope = .allKeys {
        didSet {
            refresh()
        }
    }

    private let statsRepository: StatsRepository
    private let currentSettings: PracticeSettingsSnapshot
    private let queue = DispatchQueue(label: "com.sambender.miditrainer.stats", qos: .userInitiated)

    init(currentSettings: PracticeSettingsSnapshot = PracticeSettingsSnapshot()) {
        self.currentSettings = currentSettings

        let database: Database
        do {
            database = try Database()
        } catch {
            fatalError("Failed to open database: \(error)")
        }

        self.statsRepository = StatsRepository(db: database)
        refresh()
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let filter = self.scope == .allKeys ? StatsFilter.allKeys : StatsFilter.key(self.currentSettings.key, self.currentSettings.scaleType)
            let degrees = (try? self.statsRepository.mistakeRateByDegree(filter: filter)) ?? []
            let intervals = (try? self.statsRepository.mistakeRateByInterval(filter: filter)) ?? []
            let noteIndexes = (try? self.statsRepository.mistakeRateByNoteIndex(filter: filter)) ?? []

            DispatchQueue.main.async {
                self.degreeBuckets = degrees
                self.intervalBuckets = intervals
                self.noteIndexBuckets = noteIndexes
            }
        }
    }
}
