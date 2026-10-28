import Foundation
import Network

/// A session-scoped, authenticated loopback link to the local receiver.
/// Only the selected phone can be opened; the socket never accepts an address.
@MainActor
final class NativeBluetoothRelay {
    private enum Phase { case authenticating, opening, ready }
    private var listener: NWListener?
    private var peer: NWConnection?
    private var peerID = UUID()
    private var phase = Phase.authenticating
    private var greeting = Data()
    private var queuedBytes = 0
    private var deadline: Task<Void, Never>?
    private let token = UUID().uuidString + UUID().uuidString
    private let onOpen: @MainActor () -> Void
    private let onData: @MainActor (Data) -> Void
    private let onClose: @MainActor () -> Void

    init(onOpen: @escaping @MainActor () -> Void,
         onData: @escaping @MainActor (Data) -> Void,
         onClose: @escaping @MainActor () -> Void) {
        self.onOpen = onOpen; self.onData = onData; self.onClose = onClose
    }

    func start(ready: @escaping @MainActor (UInt16, String) -> Void,
               failure: @escaping @MainActor (String) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.listener != nil else { return }
                switch state {
                case .ready:
                    guard let port = self.listener?.port?.rawValue else { return }
                    ready(port, self.token)
                case .failed(let error): failure(error.localizedDescription)
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.start(queue: .global(qos: .userInitiated))
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil, peer == nil else { connection.cancel(); return }
        peer = connection; peerID = UUID(); phase = .authenticating
        greeting = Data(); queuedBytes = 0
        let id = peerID
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.peerID == id else { return }
                switch state {
                case .ready: self.read(id)
                case .failed, .cancelled: self.closePeer()
                default: break
                }
            }
        }
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, self.peerID == id else { return }
            self.closePeer()
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func read(_ id: UUID) {
        guard peerID == id, let peer else { return }
        peer.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, ended, error in
            Task { @MainActor in
                guard let self, self.peerID == id, self.peer != nil else { return }
                if let data, !data.isEmpty {
                    if self.phase == .authenticating {
                        self.greeting.append(data)
                        guard self.greeting.count <= 128 else { self.closePeer(); return }
                        if self.greeting.contains(10) {
                            guard self.greeting == Data((self.token + "\n").utf8) else { self.closePeer(); return }
                            self.greeting = Data(); self.deadline?.cancel(); self.deadline = nil
                            self.phase = .opening
                            self.onOpen()
                        }
                    } else if self.phase == .ready { self.onData(data) }
                }
                if ended || error != nil { self.closePeer(); return }
                if self.phase != .opening { self.read(id) }
            }
        }
    }

    func bluetoothOpened() {
        guard peer != nil, phase == .opening else { return }
        phase = .ready
        send(Data("OK\n".utf8))
        read(peerID)
    }

    func send(_ data: Data) {
        guard let peer, phase == .ready else { return }
        guard queuedBytes + data.count <= 1_048_576 else { closePeer(); return }
        queuedBytes += data.count
        let id = peerID
        peer.send(content: data, completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self, self.peerID == id else { return }
                self.queuedBytes -= data.count
                if error != nil { self.closePeer() }
            }
        })
    }

    func closePeer() {
        let hadPeer = peer != nil
        peerID = UUID()
        peer?.stateUpdateHandler = nil
        peer?.cancel(); peer = nil
        deadline?.cancel(); deadline = nil
        greeting = Data(); queuedBytes = 0
        if hadPeer { onClose() }
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        closePeer()
    }
}
