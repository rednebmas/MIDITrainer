import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var model = StatsModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Scope", selection: $model.scope) {
                        ForEach(StatsModel.Scope.allCases, id: \.self) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                StatsChartSection(
                    title: "Mistake rate by degree",
                    buckets: model.degreeBuckets,
                    xLabel: "Degree"
                )

                StatsChartSection(
                    title: "Mistake rate by interval",
                    buckets: model.intervalBuckets,
                    xLabel: "Interval"
                )

                StatsChartSection(
                    title: "Mistake rate by note index",
                    buckets: model.noteIndexBuckets,
                    xLabel: "Note index"
                )
            }
            .navigationTitle("Stats")
            .onAppear {
                model.refresh()
            }
            .onReceive(settingsStore.$settings) { newSettings in
                model.updateCurrentSettings(newSettings)
            }
        }
    }
}

private struct StatsChartSection: View {
    let title: String
    let buckets: [StatBucket]
    let xLabel: String

    var body: some View {
        Section(title) {
            if buckets.isEmpty {
                Text("No data yet")
                    .foregroundStyle(.secondary)
            } else {
                Chart(buckets, id: \.label) { bucket in
                    BarMark(
                        x: .value(xLabel, bucket.label),
                        y: .value("Mistake rate", bucket.rate)
                    )
                }
                .frame(height: 220)
            }
        }
    }
}
