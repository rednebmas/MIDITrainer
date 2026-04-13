import SwiftUI

struct DynamicBackgroundView: View {
    @ObservedObject var model: PracticeModel

    var body: some View {
        RadialGradient(
            colors: [
                warmthColor.opacity(warmthOpacity),
                Color.clear
            ],
            center: UnitPoint(x: 0.5, y: 0.4),
            startRadius: 80,
            endRadius: 600
        )
        .animation(.easeInOut(duration: 0.8), value: model.currentStreak)
        .allowsHitTesting(false)
    }

    private var warmthColor: Color {
        Color(red: 1.0, green: 0.75, blue: 0.3)
    }

    private var warmthOpacity: Double {
        let streak = model.currentStreak
        switch streak {
        case 0: return 0
        case 1...2: return 0.10
        case 3...5: return 0.20
        case 6...9: return 0.35
        default: return 0.50
        }
    }
}
