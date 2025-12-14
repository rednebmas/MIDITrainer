import Foundation

struct PracticeSettingsSnapshot: Equatable, Codable {
    var key: Key
    var scaleType: ScaleType
    var excludedDegrees: Set<ScaleDegree>
    var allowedOctaves: [Int]
    var melodyLength: Int
    var bpm: Int
    var melodySourceType: MelodySourceType
    var melodyLengthMin: Int
    var melodyLengthMax: Int

    /// The effective length range for melody generation.
    var melodyLengthRange: ClosedRange<Int> {
        let minVal = max(1, min(melodyLengthMin, melodyLengthMax))
        let maxVal = max(minVal, melodyLengthMax)
        return minVal...maxVal
    }

    init(
        key: Key = Key(root: .c),
        scaleType: ScaleType = .major,
        excludedDegrees: Set<ScaleDegree> = [],
        allowedOctaves: [Int] = [3, 4, 5],
        melodyLength: Int = 4,
        bpm: Int = 80,
        melodySourceType: MelodySourceType = .billboard,
        melodyLengthMin: Int = 3,
        melodyLengthMax: Int = 6
    ) {
        self.key = key
        self.scaleType = scaleType
        self.excludedDegrees = excludedDegrees
        self.allowedOctaves = allowedOctaves.isEmpty ? [4] : allowedOctaves
        self.melodyLength = max(1, melodyLength)
        self.bpm = bpm
        self.melodySourceType = melodySourceType
        self.melodyLengthMin = max(1, melodyLengthMin)
        self.melodyLengthMax = max(1, melodyLengthMax)
    }
}

struct MelodyNote: Equatable {
    let midiNoteNumber: UInt8
    let startBeat: Double
    let durationBeats: Double
    let index: Int
}

struct MelodySequence: Equatable {
    let notes: [MelodyNote]
    let key: Key
    let scaleType: ScaleType
    let excludedDegrees: Set<ScaleDegree>
    let allowedOctaves: [Int]
    let bpm: Int
    let seed: UInt64?
    /// Source identifier for real melodies (e.g., "pop909_001")
    let sourceId: String?

    var length: Int { notes.count }

    /// Human-readable source name for display
    var sourceName: String? {
        guard let sourceId = sourceId else { return nil }
        // Convert "pop909_001" to "POP909 #001"
        if sourceId.hasPrefix("pop909_") {
            let number = sourceId.replacingOccurrences(of: "pop909_", with: "")
            return "POP909 #\(number)"
        }
        // Convert "billboard_1985_Song Name" to "Billboard 1985: Song Name"
        if sourceId.hasPrefix("billboard_") {
            let parts = sourceId.replacingOccurrences(of: "billboard_", with: "").split(separator: "_", maxSplits: 1)
            if parts.count == 2 {
                return "Billboard \(parts[0]): \(parts[1])"
            }
        }
        return sourceId
    }
}
