import SwiftUI
import Observation

@MainActor @Observable
final class ReceiverModel {
    let paths = AppPaths()
    var ssid = ""
    var password = ""
    var deviceName = "DashLink"
    var selectedPhone = ""
    var pairedPhone = ""
    var verifiedBluetoothPhone = ""
    var phones: [Phone] = []
    var isPrepared = false
    var isInstalling = false
    var isScanning = false
    var isPairing = false
    var isCheckingBluetooth = false
    var isRunning = false
    var isConnected = false
    var isStopping = false
    var viewerURL: URL?
    var status = "Let’s connect your iPhone"
    var detail = "A wireless CarPlay experiment for your Mac."
    var error: String?
    var pairingRequest: PairingCode?
    var showExperimentalChoice = false
    var showDiagnostics = false
    var diagnostics = ""
    var showSetup = true
    @ObservationIgnored private let server = ProcessController()
    @ObservationIgnored private var bluetooth: NativeBluetoothClient?
    @ObservationIgnored private var transport: NativeBluetoothClient?
    @ObservationIgnored private var relay: NativeBluetoothRelay?
    @ObservationIgnored private var activeBluetoothPhone = ""
    @ObservationIgnored private let installer = IdentityInstaller()
    @ObservationIgnored private var installation: Task<Void, Never>?
    @ObservationIgnored private var serverBuffer = ""
    @ObservationIgnored private var token = ""
    @ObservationIgnored private var stopping = false
    @ObservationIgnored private var connectAfterCheck: String?
    private let port = 18741

    init() { isPrepared = paths.isPrepared }

    var isBusy: Bool {
        isRunning || isInstalling || isScanning || isPairing || isCheckingBluetooth || isStopping
    }

    var canConnect: Bool {
        isPrepared && !isBusy && phones.contains { $0.id == selectedPhone }
        && !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && ssid.utf8.count <= 32
    }

    /// One user action performs pairing, channel verification, and startup in order.
    func connect() {
        guard canConnect else { return }
        connectAfterCheck = selectedPhone
        if canStart { connectAfterCheck = nil; start() }
        else { pair() }
    }

    var selectedPhoneHasPairing: Bool {
        pairedPhone == selectedPhone && !selectedPhone.isEmpty
        || phones.contains { $0.id == selectedPhone && $0.hasSavedPairing }
    }

    var canStart: Bool {
        isPrepared && selectedPhoneHasPairing && verifiedBluetoothPhone == selectedPhone && !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isRunning && !isInstalling && !isScanning && !isPairing && !isCheckingBluetooth && !isStopping
    }

    func prepareExperiment() {
        guard !isInstalling else { return }
        error = nil
        isInstalling = true
        status = "Preparing the experimental connection"
        detail = "Downloading and verifying the upstream preview."
        installation = Task { [weak self, installer, paths] in
            do {
                try await installer.install(into: paths)
                guard let self else { return }
                self.isPrepared = paths.isPrepared
                self.status = "Connection files are ready"
                self.detail = "Open Settings → Bluetooth on your iPhone, then find your phone below."
            } catch is CancellationError {
                self?.status = "Setup cancelled"
            } catch { self?.error = error.localizedDescription }
            self?.isInstalling = false
            self?.installation = nil
        }
    }

    private var nativeBluetooth: NativeBluetoothClient {
        if let bluetooth { return bluetooth }
        let client = NativeBluetoothClient { [weak self] in self?.receiveBluetooth($0) }
        bluetooth = client
        return client
    }

    func scan() {
        guard !isScanning && !isPairing && !isCheckingBluetooth && !isRunning else { return }
        phones = []
        selectedPhone = ""
        pairedPhone = ""
        verifiedBluetoothPhone = ""
        isScanning = true
        error = nil
        status = "Looking for your iPhone"
        detail = "Keep Settings → Bluetooth open on your iPhone."
        nativeBluetooth.scan()
    }

    func pair() {
        guard !selectedPhone.isEmpty && !isPairing && !isScanning && !isCheckingBluetooth && !isRunning else { return }
        if selectedPhoneHasPairing { checkBluetooth(); return }
        activeBluetoothPhone = selectedPhone
        verifiedBluetoothPhone = ""
        error = nil
        isPairing = true
        status = "Pairing with your iPhone"
        detail = "Compare the code in DashLink with your iPhone, then confirm on both devices."
        nativeBluetooth.pair(address: activeBluetoothPhone)
    }

    func checkBluetooth() {
        guard !selectedPhone.isEmpty && !isPairing && !isScanning && !isCheckingBluetooth && !isRunning else { return }
        activeBluetoothPhone = selectedPhone
        verifiedBluetoothPhone = ""
        error = nil
        isCheckingBluetooth = true
        status = "Checking the Bluetooth channel"
        detail = "Keep your iPhone unlocked and nearby while DashLink opens its CarPlay channel."
        nativeBluetooth.check(address: activeBluetoothPhone)
    }

    func confirmPairing(requestID: UUID) { nativeBluetooth.confirm(requestID: requestID) }
    func cancelPairing() { connectAfterCheck = nil; bluetooth?.cancel(); pairingRequest = nil }

    private func receiveBluetooth(_ event: NativeBluetoothUpdate) {
        switch event {
        case .log(let line):
            addDiagnostics(line)
            appendBluetoothLog(line)
        case .found(let phone):
            if let index = phones.firstIndex(where: { $0.id == phone.id }) { phones[index] = phone }
            else { phones.append(phone) }
        case .transportOpened, .received: break
        case .challenge(let code): pairingRequest = code
        case .confirmationSent:
            pairingRequest = nil
            status = "Mac confirmation sent"
            detail = "Confirm the matching code on your iPhone. Waiting for macOS to finish pairing."
        case .progress(let title, let message): status = title; detail = message
        case .completed(let operation, let success, let message):
            pairingRequest = nil
            switch operation {
            case .transport: break
            case .scan:
                isScanning = false
                status = phones.isEmpty ? "No phones found" : "Choose your iPhone"
                detail = "Select your iPhone to test its CarPlay Bluetooth channel."
                if !success { error = message }
            case .pair:
                isPairing = false
                if success {
                    pairedPhone = activeBluetoothPhone
                    checkBluetooth()
                } else {
                    connectAfterCheck = nil
                    pairedPhone = ""
                    verifiedBluetoothPhone = ""
                    status = "Pairing did not complete"
                    detail = "The native test stopped before a secure CarPlay connection was established."
                    error = message
                }
            case .check:
                isCheckingBluetooth = false
                if success {
                    verifiedBluetoothPhone = activeBluetoothPhone
                    status = "CarPlay Bluetooth channel verified"
                    detail = "Enter the Wi-Fi details below to try the full CarPlay connection."
                    if connectAfterCheck == selectedPhone {
                        connectAfterCheck = nil
                        start()
                    }
                } else {
                    connectAfterCheck = nil
                    verifiedBluetoothPhone = ""
                    status = "CarPlay Bluetooth channel needs attention"
                    detail = "The native test finished without opening the CarPlay Bluetooth channel."
                    error = message
                }
            }
        }
    }

    private func appendBluetoothLog(_ line: String) {
        do {
            try paths.prepareState()
            let url = paths.state.appending(path: "native-bluetooth.log")
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil,
                    attributes: [.posixPermissions: 0o600]) else { return }
            }
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.seekToEnd()
            try file.write(contentsOf: Data(line.utf8))
        } catch {
            addDiagnostics("Native Bluetooth log could not be saved: \(error.localizedDescription)\n")
        }
    }

    func start() {
        guard canStart else { return }
        error = nil
        viewerURL = nil
        serverBuffer = ""
        token = UUID().uuidString + UUID().uuidString
        stopping = false
        isRunning = true
        isConnected = false
        status = "Starting the receiver"
        detail = "Preparing the native Bluetooth connection."
        let phone = selectedPhone
        transport = NativeBluetoothClient { [weak self] event in
            guard let self else { return }
            switch event {
            case .log(let line): self.addDiagnostics(line); self.appendBluetoothLog(line)
            case .transportOpened:
                self.error = nil
                self.status = "Bluetooth connected"
                self.detail = "Exchanging CarPlay setup with your iPhone."
                self.relay?.bluetoothOpened()
            case .received(let data): self.relay?.send(data)
            case .completed(_, _, let message):
                self.relay?.closePeer()
                if !self.stopping {
                    self.status = "Wireless connection needs attention"
                    self.detail = message
                }
            default: break
            }
        }
        let relay = NativeBluetoothRelay(onOpen: { [weak self] in
            self?.transport?.openTransport(address: phone)
        }, onData: { [weak self] data in
            do { try self?.transport?.send(data) }
            catch { self?.relay?.closePeer() }
        }, onClose: { [weak self] in self?.transport?.cancel(notify: false) })
        self.relay = relay
        do {
            try relay.start(ready: { [weak self] port, secret in
                self?.launchReceiver(relayPort: port, relayToken: secret)
            }, failure: { [weak self] message in self?.launchFailed(message) })
        } catch { launchFailed(error.localizedDescription) }
    }

    private func launchReceiver(relayPort: UInt16, relayToken: String) {
        guard isRunning && !stopping && !server.isRunning else { return }
        do {
            try paths.prepareState()
            var settings = ["ssid": ssid, "password": password, "token": token,
                            "nativeBtPort": String(relayPort), "nativeBtToken": relayToken]
            if let address = NativeBluetoothClient.localAddress { settings["nativeBtAddress"] = address }
            let secrets = try JSONSerialization.data(withJSONObject: settings) + Data([10])
            let args = ["-Dorg.slf4j.simpleLogger.defaultLogLevel=info", "-cp", paths.engine.appending(path: "lib/*").path,
                        "com.playport.server.MainKt", "--desktop", "--wireless", "--http", "--device-name", deviceName,
                        "--identity-dir", paths.identity.path, "--state-dir", paths.state.appending(path: "receiver").path,
                        "--bt-address", selectedPhone, "--bt-bridge", paths.bridge.path,
                        "--airplay-port", "17000", "--http-port", String(port)]
            try server.start(executable: paths.java, arguments: args, directory: paths.engine,
                             log: paths.state.appending(path: "receiver.log"), output: { [weak self] in self?.receiveServer($0) },
                             exit: { [weak self] in self?.serverExited($0) })
            try server.send(secrets)
        } catch { launchFailed(error.localizedDescription) }
    }

    private func launchFailed(_ message: String) {
        relay?.stop(); relay = nil
        transport?.cancel(notify: false); transport = nil
        server.stop()
        isRunning = false
        isConnected = false
        status = "Receiver could not start"
        error = message
    }

    func stop() {
        connectAfterCheck = nil
        isConnected = false
        stopping = true
        isStopping = true
        status = "Disconnecting"
        viewerURL = nil
        relay?.stop(); relay = nil
        transport?.cancel(notify: false); transport = nil
        server.stop()
        if !server.isRunning { isRunning = false; isStopping = false; status = "Disconnected" }
    }

    func shutdown() {
        installation?.cancel()
        server.stop()
        bluetooth?.cancel(notify: false)
        relay?.stop(); relay = nil
        transport?.cancel(notify: false); transport = nil
    }

    func toggleSetup() { showSetup.toggle() }
    func toggleDiagnostics() { showDiagnostics.toggle() }
    func requestExperiment() { showExperimentalChoice = true }

    private func receiveServer(_ text: String) {
        addDiagnostics(text)
        serverBuffer += text
        while let end = serverBuffer.firstIndex(of: "\n") {
            let line = String(serverBuffer[..<end])
            serverBuffer.removeSubrange(...end)
            if line == "DASHLINK_READY" {
                viewerURL = URL(string: "http://127.0.0.1:\(port)/?desktop=1&token=\(token)")
                status = "Waiting for your iPhone"
                detail = "Accept the CarPlay prompt on your iPhone. If it asks for a PIN, use 3939."
                showSetup = false
            } else if line.contains("CarPlay session active") {
                isConnected = true
                status = "iPhone connected"
                detail = "CarPlay is active. The viewer will show the first frame when it arrives."
            } else if line.contains("CarPlay session ended") {
                isConnected = false
                status = "Waiting to reconnect"
                detail = "Keep both devices on the same Wi-Fi network."
            } else if line.contains("service discovery timed out") {
                status = "Phone is not responding"
                detail = "Bluetooth service discovery did not complete. CarPlay has not connected."
            } else if line.contains("wireless bootstrap failed") || line.contains("wireless bootstrap skipped") {
                status = "Wireless connection needs attention"
                detail = "The wireless handshake has not completed. Check Bluetooth permission, phone pairing and the Wi-Fi network."
            }
        }
    }

    private func serverExited(_ code: Int32) {
        relay?.stop(); relay = nil
        transport?.cancel(notify: false); transport = nil
        isRunning = false
        isConnected = false
        isStopping = false
        viewerURL = nil
        showSetup = true
        if stopping {
            status = "Disconnected"
            detail = "Your setup is ready for another connection."
        } else {
            status = "Receiver stopped"
            error = "The receiver exited (\(code)). Open diagnostics for the connection error."
        }
    }

    private func addDiagnostics(_ text: String) {
        var safe = text
        if !password.isEmpty { safe = safe.replacingOccurrences(of: password, with: "[redacted]") }
        if !token.isEmpty { safe = safe.replacingOccurrences(of: token, with: "[redacted]") }
        diagnostics = String((diagnostics + safe).suffix(24_000))
    }
}
