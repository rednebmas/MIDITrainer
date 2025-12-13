import SwiftUI

struct NoteOrbView: View {
    enum State: Equatable {
        case pending
        case awaiting
        case correct
        case error
    }

    let state: State
    let index: Int

    @SwiftUI.State private var pulseScale: CGFloat = 1.0
    @SwiftUI.State private var glowOpacity: Double = 0.4
    @SwiftUI.State private var bounceScale: CGFloat = 1.0
    @SwiftUI.State private var shakeOffset: CGFloat = 0
    @SwiftUI.State private var showErrorFlash: Bool = false
    @SwiftUI.State private var showSuccessParticles: Bool = false

    private let orbSize: CGFloat = 48

    var body: some View {
        ZStack {
            // Glow layer
            Circle()
                .fill(glowColor.opacity(glowOpacity))
                .frame(width: orbSize + 20, height: orbSize + 20)
                .blur(radius: 10)
                .scaleEffect(state == .awaiting ? pulseScale : 1.0)

            // Main orb
            Circle()
                .fill(fillColor)
                .frame(width: orbSize, height: orbSize)
                .overlay(
                    Circle()
                        .stroke(strokeColor, lineWidth: state == .awaiting ? 3 : 2)
                )
                .overlay(
                    // Error flash overlay
                    Circle()
                        .fill(Color.red.opacity(showErrorFlash ? 0.6 : 0))
                )
                .scaleEffect(bounceScale)
                .offset(x: shakeOffset)

            // Success particles
            if showSuccessParticles {
                SuccessParticlesView()
            }
        }
        .onChange(of: state) { oldState, newState in
            handleStateChange(from: oldState, to: newState)
        }
        .onAppear {
            if state == .awaiting {
                startPulseAnimation()
            }
        }
    }

    private var fillColor: Color {
        switch state {
        case .pending:
            return Color.primary.opacity(0.1)
        case .awaiting:
            return Color.primary.opacity(0.15)
        case .correct:
            return Color.green
        case .error:
            return Color.primary.opacity(0.15)
        }
    }

    private var strokeColor: Color {
        switch state {
        case .pending:
            return Color.primary.opacity(0.2)
        case .awaiting:
            return Color.yellow
        case .correct:
            return Color.green
        case .error:
            return Color.red
        }
    }

    private var glowColor: Color {
        switch state {
        case .pending:
            return Color.clear
        case .awaiting:
            return Color.yellow
        case .correct:
            return Color.green
        case .error:
            return Color.red
        }
    }

    private func handleStateChange(from oldState: State, to newState: State) {
        switch newState {
        case .awaiting:
            startPulseAnimation()
        case .correct:
            stopPulseAnimation()
            playSuccessAnimation()
        case .error:
            playErrorAnimation()
        case .pending:
            stopPulseAnimation()
            resetAnimations()
        }
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
            glowOpacity = 0.7
        }
    }

    private func stopPulseAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            pulseScale = 1.0
            glowOpacity = 0.4
        }
    }

    private func playSuccessAnimation() {
        showSuccessParticles = true

        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            bounceScale = 1.25
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.15)) {
            bounceScale = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showSuccessParticles = false
        }
    }

    private func playErrorAnimation() {
        showErrorFlash = true

        withAnimation(.linear(duration: 0.08).repeatCount(4, autoreverses: true)) {
            shakeOffset = 6
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            shakeOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.2)) {
                showErrorFlash = false
            }
        }
    }

    private func resetAnimations() {
        bounceScale = 1.0
        shakeOffset = 0
        showErrorFlash = false
        showSuccessParticles = false
    }
}

struct SuccessParticlesView: View {
    @SwiftUI.State private var particles: [(id: Int, angle: Double, distance: CGFloat, opacity: Double)] = []

    var body: some View {
        ZStack {
            ForEach(particles, id: \.id) { particle in
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .offset(
                        x: cos(particle.angle) * particle.distance,
                        y: sin(particle.angle) * particle.distance
                    )
                    .opacity(particle.opacity)
            }
        }
        .onAppear {
            createParticles()
        }
    }

    private func createParticles() {
        let particleCount = 8
        particles = (0..<particleCount).map { i in
            let angle = (Double(i) / Double(particleCount)) * 2 * .pi
            return (id: i, angle: angle, distance: 0, opacity: 1.0)
        }

        withAnimation(.easeOut(duration: 0.4)) {
            particles = particles.map { (id: $0.id, angle: $0.angle, distance: 30, opacity: 0) }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        NoteOrbView(state: .pending, index: 0)
        NoteOrbView(state: .awaiting, index: 1)
        NoteOrbView(state: .correct, index: 2)
        NoteOrbView(state: .error, index: 3)
    }
    .padding(40)
}
