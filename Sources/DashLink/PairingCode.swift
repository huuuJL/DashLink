import Foundation

struct PairingCode: Identifiable, Sendable {
    enum Mode: Sendable { case compare, enterOnPhone }
    let value: String
    var mode: Mode = .compare
    let id = UUID()
}
