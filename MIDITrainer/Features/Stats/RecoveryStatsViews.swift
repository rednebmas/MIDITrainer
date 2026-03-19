import Charts
import SwiftUI

struct RecoverySection: View {
    let recovery: RecoveryStats?

    var body: some View {
        Section("Recovery speed") {
            if let recovery {
                VStack(alignment: .leading, spacing: 6) {
                    (Text(String(format: "%.1f", recovery.averageAttempts))
                        .font(.title2.bold())
                    + Text(" attempts to recover")
                        .font(.title2))
                    Text("Based on \(recovery.totalRecoveries) sequence\(recovery.totalRecoveries == 1 ? "" : "s") that needed retries.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No recovery data yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RecoveryTrendSection: View {
    let trend: [TrendPoint]

    var body: some View {
        Section("Recovery trend") {
            if trend.count < 2 {
                Text("Need more data for trend")
                    .foregroundStyle(.secondary)
            } else {
                Chart(trend) { point in
                    LineMark(
                        x: .value("Question", point.id),
                        y: .value("Avg attempts", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "%.1f", v))
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }
}

struct RecoveryDistributionView: View {
    let buckets: [StatBucket]

    var body: some View {
        List {
            Section("Attempts to recover") {
                if buckets.isEmpty {
                    Text("No recovery data yet")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(buckets, id: \.label) { bucket in
                        BarMark(
                            x: .value("Attempts", bucket.label),
                            y: .value("Count", bucket.total)
                        )
                        .annotation(position: .top) {
                            Text("\(bucket.total)")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 220)
                }
            }
        }
        .navigationTitle("Recovery Distribution")
    }
}
