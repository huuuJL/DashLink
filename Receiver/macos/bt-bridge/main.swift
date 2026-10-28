// playport macOS Bluetooth bridge.
//
// Opens an RFCOMM channel to a paired iPhone's iAP2 service and pipes raw bytes between the
// channel and stdin/stdout, so the JVM server can speak the wireless iAP2 bootstrap over a local
// process instead of native code.
//
// Usage:
//   bt-bridge --print-address          print the local Bluetooth adapter address
//   bt-bridge --list                   list paired devices as "AA:BB:CC:DD:EE:FF Name"
//   bt-bridge --address <addr>         open RFCOMM to the device and pump stdio
//
// Use --scan and --pair for app-driven pairing. Ordinary Mac pairing from the
// iPhone's Bluetooth list may report "not supported".

import Foundation
import IOBluetooth
import Darwin

let iap2UUIDString = "00000000-deca-fade-deca-deafdecacafe"

// macOS TCC stops processes that touch Bluetooth without permission via SIGABRT.
// Turn that silent abort into actionable advice.
signal(SIGABRT) { _ in
    let hint = """
    bt-bridge was stopped by macOS: this process does not have Bluetooth permission.
    Open System Settings > Privacy & Security > Bluetooth and enable your terminal app
    (Terminal, iTerm2, VS Code, Warp, ...), then run the command again.

    """
    FileHandle.standardError.write(hint.data(using: .utf8)!)
    exit(134)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("bt-bridge: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func normalize(_ address: String) -> String {
    address.replacingOccurrences(of: ":", with: "-").lowercased()
}

/// Runs a blocking IOBluetooth call with a watchdog so missing permissions never hang the helper.
func withTimeout<T>(_ seconds: Double, _ label: String, _ operation: @escaping () -> T?) -> T? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: T?
    DispatchQueue.global().async {
        result = operation()
        semaphore.signal()
    }
    if semaphore.wait(timeout: .now() + seconds) == .timedOut {
        FileHandle.standardError.write("bt-bridge: \(label) timed out; grant Bluetooth permission to your terminal in System Settings > Privacy & Security > Bluetooth\n".data(using: .utf8)!)
        return nil
    }
    return result
}

func printAddress() {
    let address = withTimeout(3.0, "address lookup") {
        IOBluetoothHostController.default()?.addressAsString()
    }
    guard let address = address else {
        fail("local Bluetooth address unavailable")
    }
    print(address.uppercased().replacingOccurrences(of: "-", with: ":"))
}

func listPaired() {
    let paired = withTimeout(3.0, "paired-device lookup") {
        IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]
    }
    guard let devices = paired else {
        fail("paired device list unavailable")
    }
    for device in devices {
        let address = (device.addressString ?? "").uppercased().replacingOccurrences(of: "-", with: ":")
        let name = device.name ?? ""
        print("\(address) \(name)")
    }
}

final class Bridge: NSObject, IOBluetoothRFCOMMChannelDelegate, IOBluetoothDeviceAsyncCallbacks {
    private var channel: IOBluetoothRFCOMMChannel?
    private var device: IOBluetoothDevice?
    private var discoveryComplete = false
    private var connecting = false
    private var channelOpened = false
    private let checkOnly: Bool

    init(checkOnly: Bool = false) { self.checkOnly = checkOnly }

    func start(address: String) {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            fail("paired device list unavailable")
        }
        let target = normalize(address)
        guard let device = devices.first(where: { normalize($0.addressString ?? "") == target }) else {
            fail("device \(address) has no saved pairing; pair it in DashLink first")
        }
        self.device = device
        if device.isConnected() {
            queryServices()
        } else {
            connecting = true
            FileHandle.standardError.write(Data("bt-bridge: opening a Bluetooth connection using the saved pairing\n".utf8))
            let status = device.openConnection(self, withPageTimeout: 16_000, authenticationRequired: true)
            guard status == kIOReturnSuccess || device.isConnected() else {
                fail("Bluetooth connection could not start (status 0x\(String(UInt32(bitPattern: status), radix: 16)))")
            }
            if device.isConnected() { connectionComplete(device, status: kIOReturnSuccess) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                if self?.connecting == true {
                    fail("Bluetooth connection timed out before service discovery; the saved pairing was not removed")
                }
            }
        }
        withExtendedLifetime(self) { RunLoop.main.run() }
    }

    private func queryServices() {
        guard let device else { fail("selected phone is no longer available") }
        FileHandle.standardError.write(Data("bt-bridge: Bluetooth connection is open; checking CarPlay services\n".utf8))
        let uuid = IOBluetoothSDPUUID(data: Data(hexUUID: iap2UUIDString))
        if let record = device.getServiceRecord(for: uuid) {
            FileHandle.standardError.write(Data("bt-bridge: using the phone’s saved iAP2 service; verifying it by opening the channel\n".utf8))
            openChannel(record)
            return
        }
        // getServiceRecord only reads the cache. Query the selected phone first.
        let queryStatus = device.performSDPQuery(self)
        guard queryStatus == kIOReturnSuccess else {
            fail("service discovery could not start (status 0x\(String(queryStatus, radix: 16)))")
        }
        FileHandle.standardError.write(Data("bt-bridge: requesting fresh services from the selected iPhone\n".utf8))
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            if self?.discoveryComplete == false {
                if let device = self?.device {
                    let names = (device.services as? [IOBluetoothSDPServiceRecord] ?? [])
                        .map { $0.getServiceName() ?? "unnamed" }.joined(separator: ", ")
                    FileHandle.standardError.write(Data("bt-bridge: service query diagnostic: connected=\(device.isConnected()), cached services=[\(names)]\n".utf8))
                }
                fail("service discovery timed out; keep the selected iPhone unlocked and nearby")
            }
        }
    }

    func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) { }

    func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        guard connecting else { return }
        connecting = false
        guard status == kIOReturnSuccess else {
            fail("Bluetooth connection failed (status 0x\(String(UInt32(bitPattern: status), radix: 16))); the saved pairing was not removed")
        }
        queryServices()
    }

    @objc func sdpQueryComplete(_ sender: IOBluetoothDevice!, status: IOReturn) {
        discoveryComplete = true
        guard status == kIOReturnSuccess else {
            fail("service discovery failed (status 0x\(String(status, radix: 16)))")
        }
        guard let device else { fail("selected phone is no longer available") }
        let uuid = IOBluetoothSDPUUID(data: Data(hexUUID: iap2UUIDString))
        guard let record = device.getServiceRecord(for: uuid) else {
            let names = (device.services as? [IOBluetoothSDPServiceRecord] ?? [])
                .map { $0.getServiceName() ?? "unnamed" }.joined(separator: ", ")
            fail("fresh service discovery did not find iAP2; advertised services: \(names)")
        }
        openChannel(record)
    }

    private func openChannel(_ record: IOBluetoothSDPServiceRecord) {
        guard let device else { fail("selected phone is no longer available") }
        var channelID: BluetoothRFCOMMChannelID = 0
        let channelStatus = record.getRFCOMMChannelID(&channelID)
        guard channelStatus == kIOReturnSuccess else {
            fail("could not read the RFCOMM channel id (status 0x\(String(channelStatus, radix: 16)))")
        }
        var rfcommChannel: IOBluetoothRFCOMMChannel?
        // This runs in the helper process, not the UI. The synchronous result also
        // reports failures when the OS does not deliver its async completion callback.
        let openStatus = device.openRFCOMMChannelSync(&rfcommChannel, withChannelID: channelID, delegate: self)
        guard openStatus == kIOReturnSuccess, let opened = rfcommChannel else {
            fail("could not open the CarPlay Bluetooth channel (status 0x\(String(UInt32(bitPattern: openStatus), radix: 16)))")
        }
        channel = opened
        if opened.isOpen() && !channelOpened {
            rfcommChannelOpenComplete(opened, status: kIOReturnSuccess)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            if self?.channelOpened == false {
                fail("CarPlay Bluetooth channel timed out after the saved pairing connected")
            }
        }
    }

    private func pumpStdin() {
        let input = FileHandle.standardInput
        input.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                FileHandle.standardError.write("bt-bridge: stdin closed\n".data(using: .utf8)!)
                exit(0)
            }
            DispatchQueue.main.async {
                guard let channel = self.channel else { return }
                // Keep chunks below both the RFCOMM MTU and the API's 16-bit length limit.
                let chunkSize = max(1, Int(channel.getMTU()))
                for start in stride(from: 0, to: data.count, by: chunkSize) {
                    var buffer = [UInt8](data[start..<min(start + chunkSize, data.count)])
                    let status = channel.writeSync(&buffer, length: UInt16(buffer.count))
                    if status != kIOReturnSuccess {
                        fail("RFCOMM write failed (status 0x\(String(status, radix: 16)))")
                    }
                }
            }
        }
    }

    func rfcommChannelOpenComplete(_ sender: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        if error == kIOReturnSuccess {
            guard !channelOpened else { return }
            channelOpened = true
            channel = sender
            FileHandle.standardError.write("bt-bridge: RFCOMM channel open\n".data(using: .utf8)!)
            if checkOnly {
                print("CarPlay Bluetooth channel opened successfully")
                fflush(stdout)
                channel?.close()
                exit(0)
            }
            pumpStdin()
        } else {
            fail("RFCOMM open failed (status 0x\(String(UInt32(bitPattern: error), radix: 16)))")
        }
    }

    func rfcommChannelData(_ sender: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let data = Data(bytes: dataPointer, count: dataLength)
        FileHandle.standardOutput.write(data)
    }

    func rfcommChannelClosed(_ sender: IOBluetoothRFCOMMChannel!) {
        FileHandle.standardError.write("bt-bridge: RFCOMM channel closed\n".data(using: .utf8)!)
        exit(0)
    }
}

extension Data {
    init(hexUUID: String) {
        var bytes = [UInt8]()
        var hex = hexUUID.replacingOccurrences(of: "-", with: "")
        if hex.count == 4 {
            hex = "0000" + hex + "00001000800000805F9B34FB"
        }
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}

// MARK: - Inquiry and pairing
//
// macOS hides iPhones from the Bluetooth settings UI (they pair via Continuity), so the helper
// discovers and pairs them through the IOBluetooth API instead. Keep the iPhone's
// Settings > Bluetooth page open while scanning: that is what makes it discoverable.

final class Scanner: NSObject, IOBluetoothDeviceInquiryDelegate {
    private var inquiry: IOBluetoothDeviceInquiry?
    private var seen = Set<String>()

    func start(seconds: UInt8) {
        // Saved phones need not be discoverable just to appear in the picker.
        for device in IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [] {
            report(device)
        }
        guard let inquiry = IOBluetoothDeviceInquiry(delegate: self) else {
            fail("could not create a device inquiry")
        }
        self.inquiry = inquiry
        inquiry.inquiryLength = seconds
        inquiry.updateNewDeviceNames = true
        let status = inquiry.start()
        guard status == kIOReturnSuccess else {
            fail("inquiry failed to start (status 0x\(String(status, radix: 16))); grant Bluetooth permission to your terminal")
        }
        FileHandle.standardError.write("bt-bridge: scanning for \(seconds)s — keep the iPhone's Bluetooth settings page open\n".data(using: .utf8)!)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds) + 5) { [weak self] in
            guard let self else { return }
            self.inquiry?.stop()
            FileHandle.standardError.write(Data("bt-bridge: discovery time limit reached; keeping devices already found\n".utf8))
            exit(self.seen.isEmpty ? 1 : 0)
        }
        withExtendedLifetime(self) { RunLoop.main.run() }
    }

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        report(device)
    }

    private func report(_ device: IOBluetoothDevice) {
        let address = (device.addressString ?? "").uppercased().replacingOccurrences(of: "-", with: ":")
        guard !address.isEmpty, seen.insert(address).inserted else { return }
        let name = device.name ?? ""
        let kind = device.isPaired() ? "paired" : "new"
        print("\(address) \(name) [\(kind)]")
        fflush(stdout)
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        if error != kIOReturnSuccess && !aborted {
            fail("inquiry ended with status 0x\(String(error, radix: 16))")
        }
        exit(0)
    }
}

final class Pairer: NSObject, IOBluetoothDevicePairDelegate {
    private let target: String
    private let force: Bool
    private var pairing: IOBluetoothDevicePair?
    private var finished = false

    init(target: String, force: Bool) {
        self.target = target
        self.force = force
    }

    func run() {
        if let device = pairedDevice(matching: target) {
            if !force {
                print("using saved pairing with \(target)")
                exit(0)
            }
            beginPairing(with: device)
            return
        }
        // The user already selected this address from discovery. A second inquiry
        // can deliver its stopped callback before pairing is assigned and falsely
        // report "not found". Resolve the selected address directly instead.
        guard let device = IOBluetoothDevice(addressString: target) else {
            fail("selected Bluetooth address could not be resolved")
        }
        beginPairing(with: device)
    }

    private func pairedDevice(matching address: String) -> IOBluetoothDevice? {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        let normalized = normalize(address)
        return devices.first { normalize($0.addressString ?? "") == normalized }
    }

    private func beginPairing(with device: IOBluetoothDevice) {
        guard let pairing = IOBluetoothDevicePair(device: device) else {
            fail("could not create a pairing session")
        }
        self.pairing = pairing
        pairing.delegate = self
        let status = pairing.start()
        guard status == kIOReturnSuccess else {
            fail("pairing failed to start (status 0x\(String(status, radix: 16)))")
        }
        FileHandle.standardError.write("bt-bridge: pairing with \(device.addressString ?? target)…\n".data(using: .utf8)!)
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
            if !self.finished {
                self.pairing?.stop()
                fail("pairing timed out after 90s; macOS did not report a completed Bluetooth pairing")
            }
        }
        withExtendedLifetime(self) { RunLoop.main.run() }
    }

    func devicePairingStarted(_ sender: Any!) {
        FileHandle.standardError.write("bt-bridge: pairing started; a code should appear on the iPhone\n".data(using: .utf8)!)
    }

    func devicePairingConnecting(_ sender: Any!) {
        FileHandle.standardError.write("bt-bridge: link connecting…\n".data(using: .utf8)!)
    }

    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        guard let request = sender as? IOBluetoothDevicePair else {
            fail("confirmation request did not include a pairing session")
        }
        let code = String(format: "%06u", numericValue)
        print("confirm this code on the iPhone: \(code)")
        fflush(stdout)
        // The GUI and CLI both require explicit confirmation of the displayed code.
        DispatchQueue.global().async {
            let accepted = readLine() == "confirm"
            FileHandle.standardError.write(Data("bt-bridge: user confirmation received: \(accepted)\n".utf8))
            DispatchQueue.main.async {
                request.replyUserConfirmation(accepted)
                FileHandle.standardError.write(Data("bt-bridge: user confirmation delivered to Bluetooth: \(accepted)\n".utf8))
            }
        }
    }

    func deviceSimplePairingComplete(_ sender: Any!, status: BluetoothHCIEventStatus) {
        FileHandle.standardError.write(Data("bt-bridge: secure pairing completed with status 0x\(String(status, radix: 16))\n".utf8))
    }

    func devicePairingUserPasskeyNotification(_ sender: Any!, passkey: BluetoothPasskey) {
        print("enter this passkey on the iPhone: \(String(format: "%06u", passkey))")
        fflush(stdout)
    }

    func devicePairingPINCodeRequest(_ sender: Any!) {
        // Legacy PIN path; modern iPhones use numeric comparison and never reach this.
        fail("the device requested a legacy PIN code; this helper supports numeric pairing only")
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        finished = true
        if error == kIOReturnSuccess {
            print("paired with \(target)")
            exit(0)
        }
        fail("pairing failed with Bluetooth status 0x\(String(UInt32(bitPattern: error), radix: 16)); code confirmation alone does not establish the connection")
    }
}

let args = CommandLine.arguments
if args.contains("--print-address") {
    printAddress()
} else if args.contains("--list") {
    listPaired()
} else if args.contains("--scan") {
    Scanner().start(seconds: 10)
} else if let index = args.firstIndex(of: "--pair"), index + 1 < args.count {
    Pairer(target: args[index + 1], force: false).run()
} else if let index = args.firstIndex(of: "--force-pair"), index + 1 < args.count {
    Pairer(target: args[index + 1], force: true).run()
} else if let index = args.firstIndex(of: "--address"), index + 1 < args.count {
    Bridge().start(address: args[index + 1])
} else if let index = args.firstIndex(of: "--check-link"), index + 1 < args.count {
    Bridge(checkOnly: true).start(address: args[index + 1])
} else {
    fail("usage: bt-bridge --print-address | --list | --scan | --pair <addr> | --force-pair <addr> | --address <addr>")
}
