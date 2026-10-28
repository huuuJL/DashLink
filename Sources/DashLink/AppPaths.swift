import Foundation

struct AppPaths: Sendable {
    let resources: URL
    let state: URL

    init() {
        resources = Bundle.main.resourceURL ?? URL(filePath: FileManager.default.currentDirectoryPath)
        if let override = ProcessInfo.processInfo.environment["DASHLINK_STATE_DIR"] {
            state = URL(filePath: override)
        } else if let data = try? Data(contentsOf: resources.appending(path: "Install.json")),
                  let config = try? JSONDecoder().decode([String: String].self, from: data),
                  let path = config["stateDirectory"] {
            state = URL(filePath: path)
        } else {
            state = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "DashLink", directoryHint: .isDirectory)
        }
    }

    var engine: URL { resources.appending(path: "engine") }
    var java: URL { engine.appending(path: "runtime/bin/java") }
    var bridge: URL { resources.appending(path: "bt-bridge") }
    var identity: URL { state.appending(path: "identity") }
    var credentialFolder: URL { identity.appending(path: "offline-mfi") }
    var isPrepared: Bool {
        ["identity.pk8", "certificate.p7b"].allSatisfy {
            FileManager.default.fileExists(atPath: credentialFolder.appending(path: $0).path)
        }
    }

    func prepareState() throws {
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }
}
