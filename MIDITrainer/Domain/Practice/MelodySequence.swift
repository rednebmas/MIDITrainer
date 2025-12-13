import Foundation

struct PracticeSettingsSnapshot: Equatable, Codable {
    var key: Key
    var scaleType: ScaleType
    var excludedDegrees: Set<ScaleDegree>
    var allowedOctaves: [Int]
    var melodyLength: Int
    var bpm: Int

    init(
        key: Key = Key(root: .c),
        scaleType: ScaleType = .major,
        excludedDegrees: Set<ScaleDegree> = [],
        allowedOctaves: [Int] = [3, 4, 5],
        melodyLength: Int = 4,
        bpm: Int = 80
    ) {
        self.key = key
        self.scaleType = scaleType
        self.excludedDegrees = excludedDegrees
        self.allowedOctaves = allowedOctaves.isEmpty ? [4] : allowedOctaves
        self.melodyLength = max(1, melodyLength)
        self.bpm = bpm
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

    var length: Int { notes.count }
}
