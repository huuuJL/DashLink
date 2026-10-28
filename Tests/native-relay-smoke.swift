import Foundation

@main struct RelaySmokeServer {
    @MainActor static func main() async throws {
        var relay: NativeBluetoothRelay?
        relay = NativeBluetoothRelay(onOpen: { relay?.bluetoothOpened() },
                                     onData: { relay?.send($0) }, onClose: {})
        try relay?.start(ready: { port, token in
            let data = try! JSONSerialization.data(withJSONObject: ["port": Int(port), "token": token])
            FileHandle.standardOutput.write(data + Data([10]))
        }, failure: { _ in exit(1) })
        try await Task.sleep(for: .seconds(30))
        relay?.stop()
    }
}
