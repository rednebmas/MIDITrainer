import Foundation

/// The scheduling mode for how questions are presented during practice.
enum SchedulerMode: String, Codable, CaseIterable, Equatable {
    /// Reinforces incorrect sequences by re-asking them after spaced intervals.
    /// Clearance distance starts at 1, then multiplies by 3 on each failure (1 → 3 → 9 → ...).
    case spacedMistakes = "spaced_mistakes"
    
    /// No reinforcement; each question is a fresh random sequence.
    case random = "random"
    
    var displayName: String {
        switch self {
        case .spacedMistakes: return "Spaced Mistakes"
        case .random: return "Random"
        }
    }
    
    var description: String {
        switch self {
        case .spacedMistakes:
            return "Re-asks missed sequences after increasing intervals"
        case .random:
            return "Always generates fresh questions"
        }
    }
}
