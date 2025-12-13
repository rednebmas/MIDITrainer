import CoreMIDI
import Foundation

struct MIDIEndpoint: Identifiable, Equatable {
    let id: MIDIUniqueID
    let name: String
    let isOffline: Bool
}
