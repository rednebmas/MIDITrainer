import Combine
import CoreMIDI
import Foundation

final class CoreMIDIAdapter: ObservableObject, MIDIService {
    @Published private(set) var availableInputs: [MIDIEndpoint] = []
    @Published private(set) var connectedInputs: [MIDIEndpoint] = []
    @Published private(set) var availableOutputs: [MIDIEndpoint] = []
    @Published private(set) var selectedOutput: MIDIEndpoint?

    var availableInputsPublisher: AnyPublisher<[MIDIEndpoint], Never> { $availableInputs.eraseToAnyPublisher() }
    var connectedInputsPublisher: AnyPublisher<[MIDIEndpoint], Never> { $connectedInputs.eraseToAnyPublisher() }
    var availableOutputsPublisher: AnyPublisher<[MIDIEndpoint], Never> { $availableOutputs.eraseToAnyPublisher() }
    var selectedOutputPublisher: AnyPublisher<MIDIEndpoint?, Never> { $selectedOutput.eraseToAnyPublisher() }
    var noteEvents: AnyPublisher<MIDINoteEvent, Never> { noteSubject.eraseToAnyPublisher() }

    private let midiQueue = DispatchQueue(label: "com.sambender.miditrainer.midi")
    private let noteSubject = PassthroughSubject<MIDINoteEvent, Never>()

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()

    private var sourceRefs: [MIDIUniqueID: MIDIEndpointRef] = [:]
    private var destinationRefs: [MIDIUniqueID: MIDIEndpointRef] = [:]
    private var connectedSourceIDs: Set<MIDIUniqueID> = []
    private var selectedOutputID: MIDIUniqueID?
    private var desiredInputIDs: Set<MIDIUniqueID> = []

    func start() {
        midiQueue.async { [weak self] in
            guard let self else { return }
            createClientIfNeeded()
            refreshEndpoints()
        }
    }

    func stop() {
        midiQueue.async { [weak self] in
            guard let self else { return }
            disconnectAllSources()
            selectedOutputID = nil
        }
    }

    func restart() {
        midiQueue.async { [weak self] in
            guard let self else { return }
            disconnectAllSources()
            desiredInputIDs.removeAll()
            selectedOutputID = nil
            refreshEndpointsInternal()
        }
    }

    func refreshEndpoints() {
        midiQueue.async { [weak self] in
            self?.refreshEndpointsInternal()
        }
    }

    func selectOutput(_ endpoint: MIDIEndpoint?) {
        midiQueue.async { [weak self] in
            guard let self else { return }
            selectedOutputID = endpoint?.id
            updatePublishedState()
        }
    }

    func connectInput(_ endpoint: MIDIEndpoint) {
        midiQueue.async { [weak self] in
            guard let self else { return }
            desiredInputIDs.insert(endpoint.id)
            refreshEndpoints()
        }
    }

    func disconnectInput(_ endpoint: MIDIEndpoint) {
        midiQueue.async { [weak self] in
            guard let self else { return }
            desiredInputIDs.remove(endpoint.id)
            if let ref = sourceRefs[endpoint.id] {
                MIDIPortDisconnectSource(inputPort, ref)
            }
            connectedSourceIDs.remove(endpoint.id)
            updatePublishedState()
        }
    }

    func send(noteOn noteNumber: UInt8, velocity: UInt8) {
        sendMessage([0x90, noteNumber, velocity])
    }

    func send(noteOff noteNumber: UInt8) {
        sendMessage([0x80, noteNumber, 0])
    }

    private func sendMessage(_ bytes: [UInt8]) {
        midiQueue.async { [weak self] in
            guard
                let self,
                let selectedOutputID,
                let destination = destinationRefs[selectedOutputID]
            else { return }

            var packetList = MIDIPacketList()
            let packet = MIDIPacketListInit(&packetList)
            let timestamp: MIDITimeStamp = 0
            MIDIPacketListAdd(&packetList, 1024, packet, timestamp, bytes.count, bytes)
            MIDISend(self.outputPort, destination, &packetList)
        }
    }

    private func createClientIfNeeded() {
        guard client == 0 else { return }

        MIDIClientCreateWithBlock("MIDITrainerClient" as CFString, &client) { [weak self] notificationPointer in
            self?.handle(notification: notificationPointer.pointee)
        }

        MIDIInputPortCreateWithBlock(client, "MIDITrainerInput" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.handlePacketList(packetList)
        }

        MIDIOutputPortCreate(client, "MIDITrainerOutput" as CFString, &outputPort)
    }

    private func refreshEndpointsInternal() {
        let sources = collectSources()
        let destinations = collectDestinations()

        sourceRefs = Dictionary(uniqueKeysWithValues: sources.map { ($0.info.id, $0.ref) })
        destinationRefs = Dictionary(uniqueKeysWithValues: destinations.map { ($0.info.id, $0.ref) })

        reconnect(to: sources)
        pruneDisconnectedSources(currentSources: sources)
        updateSelectionIfNeeded(destinations: destinations.map(\.info))

        let availableInputs = sources.map(\.info)
        let connectedInputs = sources.compactMap { connectedSourceIDs.contains($0.info.id) ? $0.info : nil }
        let availableOutputs = destinations.map(\.info)

        DispatchQueue.main.async { [weak self] in
            self?.availableInputs = availableInputs
            self?.connectedInputs = connectedInputs
            self?.availableOutputs = availableOutputs
            self?.selectedOutput = availableOutputs.first(where: { $0.id == self?.selectedOutputID })
        }
    }

    private func reconnect(to sources: [EndpointHandle]) {
        for handle in sources where desiredInputIDs.contains(handle.info.id) && !connectedSourceIDs.contains(handle.info.id) {
            let status = MIDIPortConnectSource(inputPort, handle.ref, nil)
            if status == noErr {
                connectedSourceIDs.insert(handle.info.id)
            }
        }
    }

    private func pruneDisconnectedSources(currentSources: [EndpointHandle]) {
        let currentIDs = Set(currentSources.map { $0.info.id })
        let allowedIDs = desiredInputIDs.intersection(currentIDs)
        let removed = connectedSourceIDs.subtracting(allowedIDs)
        for removedID in removed {
            if let ref = sourceRefs[removedID] {
                MIDIPortDisconnectSource(inputPort, ref)
            }
            connectedSourceIDs.remove(removedID)
        }
    }

    private func seedDesiredInputsIfNeeded(from sources: [EndpointHandle]) {}

    private func updateSelectionIfNeeded(destinations: [MIDIEndpoint]) {
        if let selectedOutputID, destinations.contains(where: { $0.id == selectedOutputID }) {
            return
        }

        selectedOutputID = destinations.first?.id
        updatePublishedState()
    }

    private func updatePublishedState() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let selected = self.availableOutputs.first(where: { $0.id == self.selectedOutputID })
            self.selectedOutput = selected
        }
    }

    private func disconnectAllSources() {
        for id in connectedSourceIDs {
            if let ref = sourceRefs[id] {
                MIDIPortDisconnectSource(inputPort, ref)
            }
        }
        connectedSourceIDs.removeAll()

        DispatchQueue.main.async { [weak self] in
            self?.connectedInputs = []
        }
    }

    private func collectSources() -> [EndpointHandle] {
        let count = MIDIGetNumberOfSources()
        var handles: [EndpointHandle] = []
        for index in 0..<count {
            let source = MIDIGetSource(index)
            if let info = endpointInfo(for: source) {
                handles.append(EndpointHandle(info: info, ref: source))
            }
        }
        return handles
    }

    private func collectDestinations() -> [EndpointHandle] {
        let count = MIDIGetNumberOfDestinations()
        var handles: [EndpointHandle] = []
        for index in 0..<count {
            let destination = MIDIGetDestination(index)
            if let info = endpointInfo(for: destination) {
                handles.append(EndpointHandle(info: info, ref: destination))
            }
        }
        return handles
    }

    private func endpointInfo(for ref: MIDIEndpointRef) -> MIDIEndpoint? {
        let uniqueID = integerProperty(for: ref, property: kMIDIPropertyUniqueID)
        guard uniqueID != 0 else { return nil }

        let name = stringProperty(for: ref, property: kMIDIPropertyDisplayName)
            ?? stringProperty(for: ref, property: kMIDIPropertyName)
            ?? "Unknown"

        return MIDIEndpoint(id: uniqueID, name: name)
    }

    private func integerProperty(for ref: MIDIObjectRef, property: CFString) -> MIDIUniqueID {
        var value = MIDIUniqueID()
        MIDIObjectGetIntegerProperty(ref, property, &value)
        return value
    }

    private func stringProperty(for ref: MIDIObjectRef, property: CFString) -> String? {
        var unmanagedString: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(ref, property, &unmanagedString)
        guard status == noErr, let cfString = unmanagedString?.takeRetainedValue() else {
            return nil
        }
        return cfString as String
    }

    private func handle(notification: MIDINotification) {
        switch notification.messageID {
        case .msgObjectAdded, .msgObjectRemoved, .msgPropertyChanged:
            refreshEndpoints()
        default:
            break
        }
    }

    private func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        let mutableList = UnsafeMutablePointer(mutating: packetList)
        var packetPointer = withUnsafeMutablePointer(to: &mutableList.pointee.packet) { $0 }

        for _ in 0..<mutableList.pointee.numPackets {
            let packet = packetPointer.pointee
            let bytes = packetBytes(packet)
            parseMessages(bytes)
            packetPointer = MIDIPacketNext(packetPointer)
        }
    }

    private func packetBytes(_ packet: MIDIPacket) -> [UInt8] {
        let length = Int(packet.length)
        return withUnsafePointer(to: packet.data) {
            $0.withMemoryRebound(to: UInt8.self, capacity: length) { pointer in
                Array(UnsafeBufferPointer(start: pointer, count: length))
            }
        }
    }

    private func parseMessages(_ bytes: [UInt8]) {
        var index = 0
        while index < bytes.count {
            let status = bytes[index]
            guard status & 0x80 != 0 else {
                index += 1
                continue
            }

            let length = messageLength(status)
            guard index + length <= bytes.count else { break }

            if length >= 3 {
                let data1 = bytes[index + 1]
                let data2 = bytes[index + 2]
                if let event = noteEvent(status: status, data1: data1, data2: data2) {
                    noteSubject.send(event)
                }
            }

            index += length
        }
    }

    private func messageLength(_ status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0:
            return 2 // program change, channel pressure
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0:
            return 3 // note on/off, poly pressure, CC, pitch bend
        default:
            return 1 // system messages or unsupported
        }
    }

    private func noteEvent(status: UInt8, data1: UInt8, data2: UInt8) -> MIDINoteEvent? {
        switch status & 0xF0 {
        case 0x90:
            return data2 == 0 ? .noteOff(noteNumber: data1) : .noteOn(noteNumber: data1, velocity: data2)
        case 0x80:
            return .noteOff(noteNumber: data1)
        default:
            return nil
        }
    }
}

private struct EndpointHandle {
    let info: MIDIEndpoint
    let ref: MIDIEndpointRef
}
