import Foundation

/// The scheduling mode for how questions are presented during practice.
enum SchedulerMode: String, Codable, CaseIterable, Equatable {
    /// Reinforces incorrect sequences by re-asking them after spaced intervals.
    /// The gap grows by one clearance unit per successful re-ask; a mistake
    /// clears after passing at clearance × max(minPasses, failures).
    case spacedMistakes = "spaced_mistakes"

    /// Prioritizes historically weak sequences while maintaining short-term reinforcement.
    /// Queries sequences with the most first-attempt failures and uses weighted selection.
    case weaknessFocused = "weakness_focused"

    /// No reinforcement; each question is a fresh random sequence.
    case random = "random"

    /// Steers difficulty toward a target accuracy and drills missed intervals
    /// as 2-note fragments before re-asking the failed melody.
    case adaptive = "adaptive"

    var displayName: String {
        switch self {
        case .spacedMistakes: return "Spaced Mistakes"
        case .weaknessFocused: return "Weakness Focused"
        case .random: return "Random"
        case .adaptive: return "Adaptive"
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
        case .adaptive:
            return "Targets your accuracy goal; drills missed intervals as 2-note fragments"
        }
    }
}
