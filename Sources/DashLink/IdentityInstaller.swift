import Foundation
import CryptoKit

actor IdentityInstaller {
    /// Download a pinned upstream preview; never run the Android APK or include its identity in source.
    func install(into paths: AppPaths) async throws {
        try paths.prepareState()
        let source = URL(string: "https://github.com/shihabal3amri/DiPlay/releases/download/v0.2.7/DiPlay-0.2.7.apk")!
        var request = URLRequest(url: source)
        request.timeoutInterval = 120
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (download, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: download) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "DashLink", code: 1, userInfo: [NSLocalizedDescriptionKey: "The experimental package could not be downloaded."])
        }
        try Task.checkCancellation()
        let bytes = try Data(contentsOf: download, options: .mappedIfSafe)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard digest == "27b434462da7e78b1ff0987d129ed0a4b0a0e56beceaf8ec221d47150d4675bd" else {
            throw NSError(domain: "DashLink", code: 2, userInfo: [NSLocalizedDescriptionKey: "The download did not match the verified release. Setup stopped."])
        }
        let staging = paths.state.appending(path: "setup-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let unzip = Process()
        unzip.executableURL = URL(filePath: "/usr/bin/unzip")
        unzip.arguments = ["-j", "-q", download.path, "assets/offline-mfi/identity.pk8",
                           "assets/offline-mfi/certificate.p7b", "-d", staging.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw NSError(domain: "DashLink", code: 3, userInfo: [NSLocalizedDescriptionKey: "The preview package did not contain the expected connection files."])
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: paths.identity, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        for name in ["identity.pk8", "certificate.p7b"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                ofItemAtPath: staging.appending(path: name).path)
        }
        guard !FileManager.default.fileExists(atPath: paths.credentialFolder.path) else { return }
        try FileManager.default.moveItem(at: staging, to: paths.credentialFolder)
    }
}
