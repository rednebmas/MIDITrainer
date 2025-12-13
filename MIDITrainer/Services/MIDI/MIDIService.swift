import Combine
import CoreMIDI
import Foundation

protocol MIDIService: AnyObject {
    var availableInputsPublisher: AnyPublisher<[MIDIEndpoint], Never> { get }
    var connectedInputsPublisher: AnyPublisher<[MIDIEndpoint], Never> { get }
    var availableOutputsPublisher: AnyPublisher<[MIDIEndpoint], Never> { get }
    var selectedOutputPublisher: AnyPublisher<MIDIEndpoint?, Never> { get }
    var noteEvents: AnyPublisher<MIDINoteEvent, Never> { get }

    func start()
    func stop()
    func refreshEndpoints()
    func connectInput(_ endpoint: MIDIEndpoint)
    func disconnectInput(_ endpoint: MIDIEndpoint)
    func selectOutput(_ endpoint: MIDIEndpoint?)
    func send(noteOn noteNumber: UInt8, velocity: UInt8)
    func send(noteOff noteNumber: UInt8)
}
