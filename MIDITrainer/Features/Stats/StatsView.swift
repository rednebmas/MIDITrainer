import SwiftUI
import Charts
import Combine

struct StatsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var model = StatsModel()
    @State private var activeAlert: StatsAlert?

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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            activeAlert = .confirmReset
                        } label: {
                            Label("Reset my history", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .imageScale(.large)
                    }
                }
            }
            .alert(item: $activeAlert) { alert in
                switch alert {
                case .confirmReset:
                    return Alert(
                        title: Text("Reset history?"),
                        message: Text("This will clear your practice attempts, sessions, sequences, and queued mistakes."),
                        primaryButton: .destructive(Text("Reset my history")) {
                            model.resetHistory()
                        },
                        secondaryButton: .cancel()
                    )
                case .resetError(let message):
                    return Alert(
                        title: Text("Reset failed"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
            .onAppear {
                model.refresh()
            }
            .onReceive(settingsStore.$settings) { newSettings in
                model.updateCurrentSettings(newSettings)
            }
            .onReceive(model.$resetError.compactMap { $0 }) { errorMessage in
                activeAlert = .resetError(errorMessage)
            }
        }
    }
}

private enum StatsAlert: Identifiable {
    case confirmReset
    case resetError(String)

    var id: String {
        switch self {
        case .confirmReset:
            return "confirmReset"
        case .resetError(let message):
            return "resetError_\(message)"
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
