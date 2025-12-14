import Foundation

/// The scheduling mode for how questions are presented during practice.
enum SchedulerMode: String, Codable, CaseIterable, Equatable {
    /// Reinforces incorrect sequences by re-asking them after spaced intervals.
    /// Clearance distance starts at 3, then increases by 3 on each failure (3 → 6 → 9 → ...).
    case spacedMistakes = "spaced_mistakes"

    /// Prioritizes historically weak sequences while maintaining short-term reinforcement.
    /// Queries sequences with the most first-attempt failures and uses weighted selection.
    case weaknessFocused = "weakness_focused"

    /// No reinforcement; each question is a fresh random sequence.
    case random = "random"

    var displayName: String {
        switch self {
        case .spacedMistakes: return "Spaced Mistakes"
        case .weaknessFocused: return "Weakness Focused"
        case .random: return "Random"
        }
    }

    var description: String {
        switch self {
        case .spacedMistakes:
            return "Re-asks missed sequences after increasing intervals"
        case .weaknessFocused:
            return "Focuses on sequences you struggle with most"
        case .random:
            return "Always generates fresh questions"
        }
    }
}
