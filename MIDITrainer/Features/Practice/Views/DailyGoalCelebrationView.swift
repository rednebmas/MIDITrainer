import SwiftUI

struct DailyGoalCelebrationView: View {
    @ObservedObject var model: PracticeModel

    @SwiftUI.State private var particles: [CelebrationParticle] = []
    @SwiftUI.State private var bannerScale: CGFloat = 0.5
    @SwiftUI.State private var bannerOpacity: Double = 0
    @SwiftUI.State private var glowOpacity: Double = 0
    @SwiftUI.State private var hasTriggered: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.yellow.opacity(0.5),
                                Color.orange.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .position(x: geometry.size.width / 2, y: 90)
                    .opacity(glowOpacity)

                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .position(x: particle.currentX, y: particle.currentY)
                        .opacity(particle.opacity)
                }

                bannerView
                    .scaleEffect(bannerScale)
                    .opacity(bannerOpacity)
                    .position(x: geometry.size.width / 2, y: 180)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: model.questionsAnsweredToday) { oldValue, newValue in
            let goal = model.dailyGoal
            guard goal > 0 else { return }
            if !hasTriggered && oldValue < goal && newValue >= goal {
                hasTriggered = true
                triggerCelebration()
            }
        }
    }

    private var bannerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 40))
            Text("Goal Reached!")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(
            LinearGradient(
                colors: [.yellow, .orange],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.yellow.opacity(0.5), lineWidth: 2)
        )
        .shadow(color: .yellow.opacity(0.5), radius: 20)
    }

    private func triggerCelebration() {
        spawnParticles()

        withAnimation(.easeIn(duration: 0.3)) {
            glowOpacity = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                bannerScale = 1.0
                bannerOpacity = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.6)) {
                bannerOpacity = 0
                glowOpacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            particles.removeAll()
            bannerScale = 0.5
        }
    }

    private func spawnParticles() {
        let colors: [Color] = [.yellow, .orange, .green, .blue]
        let centerX: CGFloat = UIScreen.main.bounds.width / 2

        for _ in 0..<28 {
            let particle = CelebrationParticle(
                id: UUID(),
                color: colors.randomElement() ?? .yellow,
                currentX: centerX + CGFloat.random(in: -30...30),
                currentY: 90 + CGFloat.random(in: -20...20),
                opacity: 1.0,
                size: CGFloat.random(in: 6...12)
            )
            particles.append(particle)

            let id = particle.id
            let endX = centerX + CGFloat.random(in: -260...260)
            let endY = particle.currentY + CGFloat.random(in: 120...340)

            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.1)) {
                    if let idx = particles.firstIndex(where: { $0.id == id }) {
                        particles[idx].currentX = endX
                        particles[idx].currentY = endY
                        particles[idx].opacity = 0
                    }
                }
            }
        }
    }
}

private struct CelebrationParticle: Identifiable {
    let id: UUID
    let color: Color
    var currentX: CGFloat
    var currentY: CGFloat
    var opacity: Double
    let size: CGFloat
}
