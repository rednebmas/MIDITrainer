import SwiftUI

struct GameStatsBarView: View {
    let accuracy: Double?
    let accuracyCount: Int
    let questionsToday: Int
    let dailyGoal: Int
    let streak: Int

    var body: some View {
        HStack(spacing: 0) {
            // Accuracy
            accuracyView
                .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 40)

            // Daily Goal
            dailyGoalView
                .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 40)

            // Streak
            streakView
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 20)
    }

    private var accuracyView: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.primary.opacity(0.15), lineWidth: 4)
                    .frame(width: 44, height: 44)

                // Progress ring
                Circle()
                    .trim(from: 0, to: accuracy ?? 0)
                    .stroke(
                        accuracyColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: accuracy)

                // Percentage text
                Text(accuracyText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Text("accuracy")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var accuracyText: String {
        guard let acc = accuracy else { return "--" }
        return "\(Int(acc * 100))%"
    }

    private var accuracyColor: Color {
        guard let acc = accuracy else { return .gray }
        if acc >= 0.8 {
            return .green
        } else if acc >= 0.6 {
            return .orange
        } else {
            return .red
        }
    }

    private var dailyGoalView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("\(questionsToday)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("/")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("\(dailyGoal)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.15))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(dailyGoalColor)
                        .frame(width: progressWidth(totalWidth: geo.size.width))
                        .animation(.easeOut(duration: 0.3), value: questionsToday)
                }
            }
            .frame(height: 6)
            .frame(maxWidth: 80)

            Text("daily goal")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func progressWidth(totalWidth: CGFloat) -> CGFloat {
        guard dailyGoal > 0 else { return 0 }
        let progress = min(Double(questionsToday) / Double(dailyGoal), 1.0)
        return totalWidth * progress
    }

    private var dailyGoalColor: Color {
        if questionsToday >= dailyGoal {
            return .green
        } else {
            return .blue
        }
    }

    private var streakView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(fireEmoji)
                    .font(.system(size: streakFontSize))
                Text("\(streak)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: streak)
            }

            Text("streak")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var fireEmoji: String {
        if streak > 0 { return "🔥" }
        return "💨"
    }

    private var streakFontSize: CGFloat {
        if streak >= 25 { return 24 }
        if streak >= 10 { return 22 }
        if streak >= 5 { return 20 }
        return 18
    }
}

#Preview {
    VStack(spacing: 40) {
        GameStatsBarView(
            accuracy: 0.85,
            accuracyCount: 20,
            questionsToday: 24,
            dailyGoal: 30,
            streak: 5
        )

        GameStatsBarView(
            accuracy: 0.45,
            accuracyCount: 10,
            questionsToday: 30,
            dailyGoal: 30,
            streak: 12
        )

        GameStatsBarView(
            accuracy: nil,
            accuracyCount: 0,
            questionsToday: 0,
            dailyGoal: 30,
            streak: 0
        )
    }
    .padding()
}
