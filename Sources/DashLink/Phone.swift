import Foundation

struct Phone: Identifiable, Hashable, Sendable {
    let id: String
    let name: String

    var hasSavedPairing: Bool { name.hasSuffix(" [paired]") }

    var displayName: String {
        guard hasSavedPairing else { return name }
        return String(name.dropLast(" [paired]".count)) + " (saved on Mac)"
    }

    static func parse(_ line: String) -> Phone? {
        let parts = line.split(separator: " ", maxSplits: 1)
        guard parts.count == 2,
              parts[0].range(of: "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$", options: .regularExpression) != nil
        else { return nil }
        return Phone(id: String(parts[0]), name: String(parts[1]))
    }
}
