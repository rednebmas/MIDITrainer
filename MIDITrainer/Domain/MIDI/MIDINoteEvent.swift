import Foundation

enum MIDINoteEvent: Equatable {
    case noteOn(noteNumber: UInt8, velocity: UInt8)
    case noteOff(noteNumber: UInt8)
}
