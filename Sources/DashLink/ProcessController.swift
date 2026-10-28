import Foundation
import Darwin

/// Owns exactly one child. Only the main actor touches its process, handles, and callbacks.
@MainActor
final class ProcessController {
    private var process: Process?
    private var polling: Task<Void, Never>?
    private var reader: FileHandle?
    private var writer: FileHandle?
    private var input: Pipe?
    private var terminationRequested: Date?
    var isRunning: Bool { process?.isRunning == true }

    func start(executable: URL, arguments: [String], directory: URL, log: URL,
               timeout: TimeInterval? = nil,
               output: @escaping @MainActor (String) -> Void,
               exit: @escaping @MainActor (Int32) -> Void) throws {
        guard process == nil else { throw CocoaError(.executableLoad) }
        FileManager.default.createFile(atPath: log.path, contents: nil,
                                       attributes: [.posixPermissions: 0o600])
        let writeHandle = try FileHandle(forWritingTo: log)
        let readHandle = try FileHandle(forReadingFrom: log)
        let child = Process()
        let stdin = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        child.currentDirectoryURL = directory
        child.standardOutput = writeHandle
        child.standardError = writeHandle
        child.standardInput = stdin
        do { try child.run() } catch {
            try? writeHandle.close()
            try? readHandle.close()
            throw error
        }
        process = child
        reader = readHandle
        writer = writeHandle
        input = stdin
        terminationRequested = nil
        let started = Date()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.drain(output)
                if !child.isRunning {
                    self.drain(output)
                    let code = child.terminationStatus
                    self.releaseHandles()
                    self.process = nil
                    self.polling = nil
                    exit(code)
                    return
                }
                if let timeout, Date().timeIntervalSince(started) > timeout,
                   self.terminationRequested == nil { self.stop() }
                if let requested = self.terminationRequested,
                   Date().timeIntervalSince(requested) > 3, child.isRunning {
                    kill(child.processIdentifier, SIGKILL)
                }
                do { try await Task.sleep(for: .milliseconds(150)) }
                catch { return }
            }
        }
    }

    func send(_ data: Data) throws {
        guard let input, isRunning else { throw CocoaError(.fileWriteUnknown) }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func stop() {
        try? input?.fileHandleForWriting.close()
        input = nil
        if let process, process.isRunning, terminationRequested == nil {
            terminationRequested = Date()
            process.terminate()
        }
    }

    private func drain(_ output: (String) -> Void) {
        guard let reader else { return }
        for _ in 0..<16 {
            guard let data = try? reader.read(upToCount: 65_536), !data.isEmpty else { return }
            output(String(decoding: data, as: UTF8.self))
        }
    }

    private func releaseHandles() {
        try? reader?.close()
        try? writer?.close()
        try? input?.fileHandleForWriting.close()
        reader = nil
        writer = nil
        input = nil
        terminationRequested = nil
    }
}
