import Foundation

enum NoteName: Int, CaseIterable, Equatable {
    case c = 0
    case cSharp = 1
    case d = 2
    case dSharp = 3
    case e = 4
    case f = 5
    case fSharp = 6
    case g = 7
    case gSharp = 8
    case a = 9
    case aSharp = 10
    case b = 11

    var displayName: String {
        switch self {
        case .c: return "C"
        case .cSharp: return "C#"
        case .d: return "D"
        case .dSharp: return "D#"
        case .e: return "E"
        case .f: return "F"
        case .fSharp: return "F#"
        case .g: return "G"
        case .gSharp: return "G#"
        case .a: return "A"
        case .aSharp: return "A#"
        case .b: return "B"
        }
    }
}

struct Key: Equatable {
    let root: NoteName
}

enum ScaleType: CaseIterable, Equatable {
    case major
    case naturalMinor
    case dorian
    case mixolydian

    fileprivate var semitoneOffsets: [Int] {
        switch self {
        case .major:
            return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor:
            return [0, 2, 3, 5, 7, 8, 10]
        case .dorian:
            return [0, 2, 3, 5, 7, 9, 10]
        case .mixolydian:
            return [0, 2, 4, 5, 7, 9, 10]
        }
    }
}

enum ScaleDegree: Int, CaseIterable, Hashable {
    case i = 1
    case ii = 2
    case iii = 3
    case iv = 4
    case v = 5
    case vi = 6
    case vii = 7
}

struct Scale: Equatable {
    let key: Key
    let type: ScaleType

    func semitoneOffset(for degree: ScaleDegree) -> Int? {
        guard let index = ScaleDegree.allCases.firstIndex(of: degree) else { return nil }
        return type.semitoneOffsets[index]
    }

    func midiNoteNumber(for degree: ScaleDegree, octave: Int) -> UInt8? {
        guard let offset = semitoneOffset(for: degree) else { return nil }
        let midiNumber = ((octave + 1) * 12) + key.root.rawValue + offset
        guard (0...127).contains(midiNumber) else { return nil }
        return UInt8(midiNumber)
    }
}

struct Interval: Equatable {
    let semitones: Int
}
