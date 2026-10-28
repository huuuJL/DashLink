import Foundation

@main struct NativeSmoke {
    @MainActor static func main() async throws {
        precondition(Phone.parse("AA:BB:CC:DD:EE:FF My iPhone [paired]")?.name == "My iPhone [paired]")
        precondition(Phone.parse("bt-bridge: failed") == nil)
        let root = URL(filePath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let child = ProcessController()
        var captured = ""
        var exited: Int32?
        try child.start(executable: URL(filePath: "/bin/cat"), arguments: [], directory: root,
                        log: root.appending(path: "cat.log"), output: { captured += $0 }, exit: { exited = $0 })
        try child.send(Data("private-input-round-trip\n".utf8))
        for _ in 0..<30 {
            if captured.contains("private-input-round-trip") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(captured.contains("private-input-round-trip"))
        child.stop()
        for _ in 0..<40 {
            if exited != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(exited != nil && !child.isRunning)
        exited = nil
        let started = Date()
        try child.start(executable: URL(filePath: "/bin/sleep"), arguments: ["30"], directory: root,
                        log: root.appending(path: "timeout.log"), timeout: 0.2, output: { _ in }, exit: { exited = $0 })
        for _ in 0..<50 {
            if exited != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        precondition(exited != nil && Date().timeIntervalSince(started) < 5)
        print("Native smoke checks passed: device parsing, private input, output capture, stop, and timeout.")
    }
}
