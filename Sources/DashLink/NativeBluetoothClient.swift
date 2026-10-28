import Foundation
import IOBluetooth

enum BluetoothOperation: String, Sendable { case scan, pair, check, transport }

enum NativeBluetoothUpdate {
    case log(String)
    case found(Phone)
    case challenge(PairingCode)
    case transportOpened
    case received(Data)
    case confirmationSent
    case progress(String, String)
    case completed(BluetoothOperation, Bool, String)
}

@MainActor
final class NativeBluetoothClient {
    private enum Phase { case idle, scanning, pairing, connecting, discovering, channel, streaming }
    private var phase = Phase.idle
    private var operation = BluetoothOperation.scan
    private var attempt = UUID()
    private var started = Date()
    private var adapter: BluetoothDelegateAdapter?
    private var inquiry: IOBluetoothDeviceInquiry?
    private var pairing: IOBluetoothDevicePair?
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var timeout: Task<Void, Never>?
    private var confirmation = PairingConfirmationGate()
    private var seen = Set<String>()
    private var earlyData = Data()
    private var sentBytes = 0
    private var receivedBytes = 0
    private let update: @MainActor (NativeBluetoothUpdate) -> Void

    init(update: @escaping @MainActor (NativeBluetoothUpdate) -> Void) { self.update = update }

    private func begin(_ operation: BluetoothOperation, phase: Phase, seconds: Double) {
        cancel(notify: false)
        self.operation = operation
        self.phase = phase
        attempt = UUID()
        started = Date()
        seen.removeAll()
        sentBytes = 0; receivedBytes = 0
        let id = attempt
        adapter = BluetoothDelegateAdapter { [weak self] event, onMain in
            Task { @MainActor in
                guard let self, self.attempt == id, self.phase != .idle else { return }
                self.receive(event, onMain: onMain)
            }
        }
        log("begin \(operation.rawValue); native app process; attempt=\(id)")
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.attempt == id, self.phase != .idle else { return }
            let success = self.phase == .scanning && !self.seen.isEmpty
            self.finish(success, success ? "Scan finished with saved and discovered devices." : "No completion callback arrived during the native \(self.operation.rawValue) test.")
        }
    }

    func scan() {
        begin(.scan, phase: .scanning, seconds: 15)
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
            adapter?.deviceInquiryDeviceFound(nil, device: device)
        }
        guard let inquiry = IOBluetoothDeviceInquiry(delegate: adapter) else {
            finish(false, "macOS could not create Bluetooth discovery."); return
        }
        self.inquiry = inquiry
        inquiry.inquiryLength = 10
        inquiry.updateNewDeviceNames = true
        let status = inquiry.start()
        if status != kIOReturnSuccess { finish(false, "Discovery could not start: \(hex(status)).") }
    }

    func pair(address: String) {
        begin(.pair, phase: .pairing, seconds: 90)
        guard let device = IOBluetoothDevice(addressString: address),
              let pairing = IOBluetoothDevicePair(device: device) else {
            finish(false, "macOS could not create the selected pairing session."); return
        }
        self.device = device
        self.pairing = pairing
        pairing.delegate = adapter
        let status = pairing.start()
        log("pair.start returned \(hex(status))")
        if status != kIOReturnSuccess { finish(false, "Pairing could not start: \(hex(status)).") }
    }

    func confirm(requestID: UUID) {
        guard phase == .pairing, confirmation.consume(requestID), let pairing else {
            log("ignored stale or already-consumed confirmation"); return
        }
        pairing.replyUserConfirmation(true)
        log("explicit user confirmation delivered directly to macOS")
        update(.confirmationSent)
    }

    func check(address: String) { connect(address: address, operation: .check) }
    func openTransport(address: String) { connect(address: address, operation: .transport) }

    static var localAddress: String? { IOBluetoothHostController.default()?.addressAsString() }

    func send(_ data: Data) throws {
        guard phase == .streaming, let channel, channel.isOpen() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let size = max(1, min(Int(channel.getMTU()), Int(UInt16.max)))
        for offset in stride(from: 0, to: data.count, by: size) {
            var chunk = [UInt8](data[offset..<min(offset + size, data.count)])
            let status = channel.writeSync(&chunk, length: UInt16(chunk.count))
            guard status == kIOReturnSuccess else {
                finish(false, "Bluetooth write failed: \(hex(status)).")
                throw CocoaError(.fileWriteUnknown)
            }
        }
        if sentBytes == 0 { log("first Bluetooth write: \(data.count) bytes") }
        sentBytes += data.count
    }

    private func connect(address: String, operation: BluetoothOperation) {
        begin(operation, phase: .connecting, seconds: 40)
        guard let device = IOBluetoothDevice(addressString: address) else {
            finish(false, "The selected phone could not be resolved."); return
        }
        self.device = device
        log("saved pairing=\(device.isPaired()); basic connection=\(device.isConnected())")
        if device.isConnected() { findService(); return }
        let status = device.openConnection(adapter, withPageTimeout: 16_000, authenticationRequired: true)
        log("connection request returned \(hex(status))")
        if status != kIOReturnSuccess {
            if device.isConnected() { findService() }
            else { finish(false, "Bluetooth connection could not start: \(hex(status)).") }
        }
    }

    private func findService() {
        guard let device else { return }
        phase = .discovering
        update(.progress("Bluetooth link opened", "Checking the secure CarPlay channel inside DashLink."))
        if let record = iapRecord(device) { openChannel(record); return }
        let status = device.performSDPQuery(adapter)
        log("service query request returned \(hex(status))")
        if status != kIOReturnSuccess { finish(false, "Service discovery could not start: \(hex(status)).") }
    }

    private func iapRecord(_ device: IOBluetoothDevice) -> IOBluetoothSDPServiceRecord? {
        // Both phone-side iAP services advertise RFCOMM. Prefer the v2 record.
        for text in ["02030302-1d19-415f-86f2-22a2106a0a77", "00000000-deca-fade-deca-deafdecacafe"] {
            let bytes = stride(from: 0, to: 32, by: 2).map { offset -> UInt8 in
                let hex = text.replacingOccurrences(of: "-", with: "")
                let start = hex.index(hex.startIndex, offsetBy: offset)
                return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
            }
            if let record = device.getServiceRecord(for: IOBluetoothSDPUUID(data: Data(bytes))) { return record }
        }
        return nil
    }

    private func openChannel(_ record: IOBluetoothSDPServiceRecord) {
        guard let device else { return }
        var id: BluetoothRFCOMMChannelID = 0
        let status = record.getRFCOMMChannelID(&id)
        guard status == kIOReturnSuccess, id != 0 else {
            finish(false, "The phone’s CarPlay service has no usable channel."); return
        }
        phase = .channel
        log("opening iAP RFCOMM channel \(id)")
        var opened: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&opened, withChannelID: id, delegate: adapter)
        channel = opened
        log("channel request returned \(hex(result))")
        if result != kIOReturnSuccess { finish(false, "CarPlay channel could not start: \(hex(result)).") }
    }

    private func receive(_ event: BluetoothCallback, onMain: Bool) {
        switch event {
        case .found(let phone):
            if phase == .scanning, seen.insert(phone.id).inserted { update(.found(phone)) }
        case .inquiryEnded(let code, let aborted):
            guard phase == .scanning else { return }
            log("discovery callback \(hex(code)), aborted=\(aborted), mainThread=\(onMain)")
            finish(code == 0 || !seen.isEmpty, code == 0 ? "Discovery complete." : "Discovery ended with \(hex(code)).")
        case .pairingStarted:
            log("pairing started callback; mainThread=\(onMain)")
        case .pairingConnected:
            log("pairing baseband connected callback; mainThread=\(onMain)")
        case .confirmation(let value, let sender):
            guard phase == .pairing, let pairing, ObjectIdentifier(pairing) == sender else { return }
            log("numeric comparison requested; mainThread=\(onMain)")
            update(.challenge(confirmation.request(value)))
        case .passkey(let value):
            guard phase == .pairing else { return }
            update(.challenge(confirmation.request(value, mode: .enterOnPhone)))
        case .legacyPIN:
            finish(false, "The phone requested a legacy PIN instead of numeric comparison.")
        case .simplePairingEnded(let code):
            log("secure pairing callback status=\(code), mainThread=\(onMain)")
        case .pairingEnded(let code):
            guard phase == .pairing else { return }
            log("pairing completion \(hex(code)), mainThread=\(onMain)")
            finish(code == 0, code == 0 ? "macOS confirmed pairing complete." : "Native macOS pairing ended with status \(hex(code)).")
        case .connectionEnded(let code):
            guard phase == .connecting else { return }
            log("connection callback \(hex(code)), mainThread=\(onMain)")
            if code == 0 { findService() }
            else { finish(false, "Native Bluetooth connection failed: \(hex(code)).") }
        case .servicesEnded(let code):
            guard phase == .discovering else { return }
            log("service query callback \(hex(code)), mainThread=\(onMain)")
            if code == 0, let device, let record = iapRecord(device) { openChannel(record) }
            else { finish(false, "CarPlay service discovery did not complete: \(hex(code)).") }
        case .channelOpened(let code):
            guard phase == .channel else { return }
            let encrypted = device.map { $0.getEncryptionMode() != 0 } ?? false
            let open = channel?.isOpen() == true
            log("channel callback \(hex(code)); open=\(open); encrypted=\(encrypted); mainThread=\(onMain)")
            // macOS 27.2 can report getEncryptionMode() == 0 after its own log
            // confirms successful AES-CCM encryption. It explicitly skips updating
            // this legacy field. Do not turn that stale readout into a channel error.
            // The OS still enforces RFCOMM authentication/encryption; we never lower it.
            let success = code == 0 && open
            if success && operation == .transport {
                phase = .streaming
                timeout?.cancel(); timeout = nil
                update(.transportOpened)
                if !earlyData.isEmpty { update(.received(earlyData)); earlyData = Data() }
            } else {
                finish(success, success ? "The phone’s CarPlay Bluetooth channel opened successfully." : "Native CarPlay channel failed: \(hex(code)); open=\(open).")
            }
        case .received(let data):
            if receivedBytes == 0 { log("first Bluetooth receive: \(data.count) bytes") }
            receivedBytes += data.count
            if phase == .streaming { update(.received(data)) }
            else if phase == .channel && operation == .transport {
                guard earlyData.count + data.count <= 65_536 else {
                    finish(false, "Bluetooth startup buffer exceeded its limit."); return
                }
                earlyData.append(data)
            }
        case .channelClosed:
            if phase == .channel || phase == .streaming { finish(false, "The CarPlay Bluetooth channel closed.") }
        }
    }

    func cancel(notify: Bool = true) {
        guard phase != .idle else { return }
        if notify { finish(false, "Bluetooth test cancelled.") }
        else { cleanup() }
    }

    private func finish(_ success: Bool, _ message: String) {
        guard phase != .idle else { return }
        let completed = operation
        log("finish \(completed.rawValue): success=\(success); \(message)")
        cleanup()
        update(.completed(completed, success, message))
    }

    private func cleanup() {
        phase = .idle
        attempt = UUID() // Reject callbacks from the previous session.
        timeout?.cancel(); timeout = nil
        confirmation.clear()
        earlyData = Data()
        inquiry?.stop(); inquiry = nil
        pairing?.delegate = nil
        pairing?.stop(); pairing = nil
        channel?.setDelegate(nil)
        channel?.close(); channel = nil
        device = nil
        adapter = nil
    }

    private func log(_ message: String) {
        update(.log(String(format: "[native-bt +%.3fs] %@\n", Date().timeIntervalSince(started), message)))
    }
    private func hex(_ status: Int32) -> String { "0x" + String(UInt32(bitPattern: status), radix: 16) }
}
