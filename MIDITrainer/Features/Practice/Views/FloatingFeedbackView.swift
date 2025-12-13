import SwiftUI

enum FeedbackType {
    case perfect
    case correct
    case tryAgain

    var text: String {
        switch self {
        case .perfect: return "Perfect!"
        case .correct: return "Correct"
        case .tryAgain: return "Replaying..."
        }
    }

    var color: Color {
        switch self {
        case .perfect: return .green
        case .correct: return .blue
        case .tryAgain: return .orange
        }
    }

    var icon: String {
        switch self {
        case .perfect: return "star.fill"
        case .correct: return "checkmark.circle.fill"
        case .tryAgain: return "arrow.counterclockwise"
        }
    }
}

struct FloatingFeedbackView: View {
    let type: FeedbackType
    let isVisible: Bool

    @SwiftUI.State private var scale: CGFloat = 0.5
    @SwiftUI.State private var opacity: Double = 0
    @SwiftUI.State private var yOffset: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: type.icon)
                .font(.title2)
            Text(type.text)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(type.color)
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(y: yOffset)
        .onChange(of: isVisible) { _, visible in
            if visible {
                showFeedback()
            } else {
                hideFeedback()
            }
        }
        .onAppear {
            if isVisible {
                showFeedback()
            }
        }
    }

    private func showFeedback() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            scale = 1.0
            opacity = 1.0
            yOffset = 0
        }
    }

    private func hideFeedback() {
        withAnimation(.easeOut(duration: 0.3)) {
            scale = 0.8
            opacity = 0
            yOffset = -20
        }
    }
}

struct FloatingFeedbackOverlay: View {
    let feedbackType: FeedbackType?

    @SwiftUI.State private var isVisible = false

    var body: some View {
        ZStack {
            if let type = feedbackType {
                FloatingFeedbackView(type: type, isVisible: isVisible)
            }
        }
        .onChange(of: feedbackType) { _, newValue in
            if newValue != nil {
                isVisible = true
                // Auto-hide after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    isVisible = false
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        FloatingFeedbackView(type: .perfect, isVisible: true)
        FloatingFeedbackView(type: .correct, isVisible: true)
        FloatingFeedbackView(type: .tryAgain, isVisible: true)
    }
}
