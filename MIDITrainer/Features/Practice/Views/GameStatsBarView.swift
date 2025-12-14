import SwiftUI

struct GameStatsBarView: View {
    let accuracy: Double?
    let accuracyCount: Int
    let questionsToday: Int
    let dailyGoal: Int
    let streak: Int
    var onAccuracyTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 40) {
            // Accuracy
            Button(action: { onAccuracyTap?() }) {
                accuracyView
            }
            .buttonStyle(.plain)

            // Daily Goal
            dailyGoalView

            // Streak
            streakView
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 16)
        .background {
            // Colored glows that bleed through the glass
            ZStack {
                // Accuracy glow (left)
                Circle()
                    .fill(accuracyColor.opacity(0.2))
                    .blur(radius: 30)
                    .frame(width: 80, height: 80)
                    .offset(x: -90)

                // Daily goal glow (center)
                Circle()
                    .fill(dailyGoalColor.opacity(0.25))
                    .blur(radius: 25)
                    .frame(width: 70, height: 70)

                // Streak glow (right)
                Circle()
                    .fill(streakColor.opacity(0.2))
                    .blur(radius: 30)
                    .frame(width: 80, height: 80)
                    .offset(x: 90)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Accuracy View

    private var accuracyView: some View {
        HStack(spacing: 10) {
            // Ring
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.1), lineWidth: 3.5)
                    .frame(width: 40, height: 40)

                Circle()
                    .trim(from: 0, to: accuracy ?? 0)
                    .stroke(
                        accuracyColor,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: accuracy)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(accuracyText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("accuracy")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accuracyText: String {
        guard let acc = accuracy else { return "--%" }
        return "\(Int(acc * 100))%"
    }

    private var accuracyColor: Color {
        guard let acc = accuracy else { return .gray }
        if acc >= 0.8 { return .green }
        if acc >= 0.6 { return .orange }
        return .red
    }

    // MARK: - Daily Goal View

    private var dailyGoalView: some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                Text("\(questionsToday)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: questionsToday)
                Text("/\(dailyGoal)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 56, height: 5)

                Capsule()
                    .fill(dailyGoalColor)
                    .frame(width: progressWidth, height: 5)
                    .animation(.easeOut(duration: 0.3), value: questionsToday)
            }

            Text("daily goal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var progressWidth: CGFloat {
        guard dailyGoal > 0 else { return 0 }
        let progress = min(Double(questionsToday) / Double(dailyGoal), 1.0)
        return 56 * progress
    }

    private var dailyGoalColor: Color {
        questionsToday >= dailyGoal ? .green : .blue
    }

    // MARK: - Streak View

    private var streakView: some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(streak)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3), value: streak)

                Text("streak")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(fireEmoji)
                .font(.system(size: streakFontSize))
        }
    }

    private var fireEmoji: String {
        streak > 0 ? "🔥" : "💨"
    }

    private var streakFontSize: CGFloat {
        if streak >= 25 { return 28 }
        if streak >= 10 { return 24 }
        if streak >= 5 { return 22 }
        return 20
    }

    private var streakColor: Color {
        if streak >= 10 { return .orange }
        if streak > 0 { return .yellow }
        return .gray
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

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
}
