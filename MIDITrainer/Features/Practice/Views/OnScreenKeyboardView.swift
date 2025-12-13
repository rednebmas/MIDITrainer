import SwiftUI

struct OnScreenKeyboardView: View {
    let octaves: [Int]
    let onNoteOn: (UInt8) -> Void
    let onNoteOff: (UInt8) -> Void

    // Key dimensions based on reference design, scaled for touch
    private let whiteKeyWidth: CGFloat = 44
    private let whiteKeyHeight: CGFloat = 160
    private let blackKeyWidth: CGFloat = 30
    private let blackKeyHeight: CGFloat = 100

    private var octaveWidth: CGFloat {
        // 7 white keys + 6 gaps of 2pt each
        whiteKeyWidth * 7 + 2 * 6
    }

    // The extra key at the end (octave note)
    private var extraKeyWidth: CGFloat {
        whiteKeyWidth + 2
    }

    private var highestOctaveMidiBase: Int {
        let highest = octaves.max() ?? 4
        return (highest + 1) * 12
    }

    var body: some View {
        GeometryReader { geo in
            // Include extra key width in calculation
            let totalContentWidth = octaveWidth * CGFloat(octaves.count) + extraKeyWidth + 32
            let needsScroll = totalContentWidth > geo.size.width

            if needsScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    keyboardContent
                        .padding(.horizontal, 16)
                }
            } else {
                HStack {
                    Spacer()
                    keyboardContent
                    Spacer()
                }
            }
        }
        .frame(height: whiteKeyHeight + 20)
    }

    private var keyboardContent: some View {
        HStack(spacing: 0) {
            ForEach(octaves.sorted(), id: \.self) { octave in
                OctaveView(
                    octave: octave,
                    whiteKeyWidth: whiteKeyWidth,
                    whiteKeyHeight: whiteKeyHeight,
                    blackKeyWidth: blackKeyWidth,
                    blackKeyHeight: blackKeyHeight,
                    onNoteOn: onNoteOn,
                    onNoteOff: onNoteOff
                )
            }
            // Extra key: the octave note (root of next octave)
            let octaveNoteMidi = UInt8(highestOctaveMidiBase + 12) // C of next octave
            WhiteKeyView(
                width: whiteKeyWidth,
                height: whiteKeyHeight,
                onNoteOn: { onNoteOn(octaveNoteMidi) },
                onNoteOff: { onNoteOff(octaveNoteMidi) }
            )
            .padding(.leading, 2)
        }
    }
}

private struct OctaveView: View {
    let octave: Int
    let whiteKeyWidth: CGFloat
    let whiteKeyHeight: CGFloat
    let blackKeyWidth: CGFloat
    let blackKeyHeight: CGFloat
    let onNoteOn: (UInt8) -> Void
    let onNoteOff: (UInt8) -> Void

    // White key note offsets within octave (C, D, E, F, G, A, B)
    private let whiteKeyOffsets: [Int] = [0, 2, 4, 5, 7, 9, 11]
    // Black key positions (index of white key to the left) and note offsets
    private let blackKeyData: [(whiteIndex: Int, noteOffset: Int)] = [
        (0, 1),  // C# after C
        (1, 3),  // D# after D
        (3, 6),  // F# after F
        (4, 8),  // G# after G
        (5, 10), // A# after A
    ]

    private var baseMidi: Int { (octave + 1) * 12 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // White keys
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { index in
                    let midiNote = UInt8(baseMidi + whiteKeyOffsets[index])
                    WhiteKeyView(
                        width: whiteKeyWidth,
                        height: whiteKeyHeight,
                        onNoteOn: { onNoteOn(midiNote) },
                        onNoteOff: { onNoteOff(midiNote) }
                    )
                }
            }

            // Black keys
            ForEach(blackKeyData, id: \.noteOffset) { data in
                let midiNote = UInt8(baseMidi + data.noteOffset)
                let xOffset = CGFloat(data.whiteIndex) * (whiteKeyWidth + 2) + whiteKeyWidth - blackKeyWidth / 2
                BlackKeyView(
                    width: blackKeyWidth,
                    height: blackKeyHeight,
                    onNoteOn: { onNoteOn(midiNote) },
                    onNoteOff: { onNoteOff(midiNote) }
                )
                .offset(x: xOffset)
            }
        }
    }
}

private struct WhiteKeyView: View {
    let width: CGFloat
    let height: CGFloat
    let onNoteOn: () -> Void
    let onNoteOff: () -> Void

    @GestureState private var isPressed = false
    @State private var showingCorrect = false
    @State private var showingWrong = false

    private var fillGradient: LinearGradient {
        if showingCorrect {
            return LinearGradient(
                colors: [Color(hex: "63DC50"), Color(hex: "3C962E")],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if showingWrong {
            return LinearGradient(
                colors: [Color(hex: "DC5050"), Color(hex: "962E2E")],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if isPressed {
            return LinearGradient(
                colors: [Color(hex: "E8E8E8"), Color(hex: "D0D0D0")],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color(hex: "FFFFFF"), Color(hex: "F0F0F0")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(fillGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "8E9AA3"), lineWidth: 1)
            )
            .frame(width: width, height: height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        if !state {
                            state = true
                            onNoteOn()
                        }
                    }
                    .onEnded { _ in
                        onNoteOff()
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0)
                    .onEnded { _ in }
            )
    }
}

private struct BlackKeyView: View {
    let width: CGFloat
    let height: CGFloat
    let onNoteOn: () -> Void
    let onNoteOff: () -> Void

    @GestureState private var isPressed = false

    private var fillGradient: LinearGradient {
        if isPressed {
            return LinearGradient(
                colors: [Color(hex: "3A444D"), Color(hex: "1E2226")],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [Color(hex: "475461"), Color(hex: "282D31")],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(fillGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color(hex: "2D2D2D"), lineWidth: 1)
            )
            .frame(width: width, height: height)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        if !state {
                            state = true
                            onNoteOn()
                        }
                    }
                    .onEnded { _ in
                        onNoteOff()
                    }
            )
    }
}

// MARK: - Color Extension

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    VStack {
        Text("On-Screen Keyboard")
            .font(.headline)
        OnScreenKeyboardView(
            octaves: [3, 4, 5],
            onNoteOn: { note in print("Note on: \(note)") },
            onNoteOff: { note in print("Note off: \(note)") }
        )
    }
    .padding()
}
