import Foundation

enum IntervalName {
    private static let names = [
        "U", "m2", "M2", "m3", "M3", "P4", "TT", "P5", "m6", "M6", "m7", "M7", "8ve",
    ]

    static func label(semitones: Int) -> String {
        let magnitude = abs(semitones)
        let arrow = semitones > 0 ? "↑" : (semitones < 0 ? "↓" : "")
        let name = magnitude < names.count ? names[magnitude] : "\(magnitude)st"
        return arrow + name
    }
}
