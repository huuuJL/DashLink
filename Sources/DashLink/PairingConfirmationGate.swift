import Foundation

struct PairingConfirmationGate {
    private(set) var pending: PairingCode?

    mutating func request(_ value: String, mode: PairingCode.Mode = .compare) -> PairingCode {
        let challenge = PairingCode(value: value, mode: mode)
        pending = challenge
        return challenge
    }

    mutating func consume(_ id: UUID) -> Bool {
        guard let pending, pending.id == id, pending.mode == .compare else { return false }
        self.pending = nil
        return true
    }

    mutating func clear() { pending = nil }
}
