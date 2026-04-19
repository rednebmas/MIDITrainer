import SwiftUI

struct StreakMilestoneBannerView: View {
    @ObservedObject var model: PracticeModel

    @SwiftUI.State private var visibleMilestone: Int?
    @SwiftUI.State private var bannerScale: CGFloat = 0.8
    @SwiftUI.State private var bannerOpacity: Double = 0

    private static let milestones: Set<Int> = [1, 3, 5, 7, 10, 15, 20, 25, 50]

    var body: some View {
        VStack {
            if let milestone = visibleMilestone {
                bannerContent(for: milestone)
                    .scaleEffect(bannerScale)
                    .opacity(bannerOpacity)
                    .padding(.top, 110)
            }
            Spacer()
        }
        .allowsHitTesting(false)
        .onChange(of: model.currentStreak) { oldValue, newValue in
            if newValue > oldValue && Self.milestones.contains(newValue) {
                showBanner(for: newValue)
            }
        }
    }

    private func bannerContent(for milestone: Int) -> some View {
        HStack(spacing: 16) {
            Text("🔥")
                .font(.system(size: 52))
            Text(text(for: milestone))
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .yellow],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.6), Color.yellow.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        )
        .shadow(color: .orange.opacity(0.4), radius: 24)
    }

    private func text(for milestone: Int) -> String {
        milestone == 1 ? "FIRST PERFECT!" : "\(milestone) STREAK"
    }

    private func showBanner(for milestone: Int) {
        visibleMilestone = milestone
        bannerScale = 0.8
        bannerOpacity = 0

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            bannerScale = 1.0
            bannerOpacity = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.5)) {
                bannerOpacity = 0
                bannerScale = 1.1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            if visibleMilestone == milestone {
                visibleMilestone = nil
            }
        }
    }
}
