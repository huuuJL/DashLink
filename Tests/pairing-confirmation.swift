import Foundation

@main struct PairingConfirmationCheck {
    static func main() {
        var gate = PairingConfirmationGate()
        precondition(!gate.consume(UUID()), "No pending request may be confirmed")
        let first = gate.request("123456")
        precondition(gate.pending?.id == first.id, "Receiving a code must leave it awaiting user input")
        let second = gate.request("654321")
        precondition(!gate.consume(first.id), "An older dialog must never approve the current pairing request")
        precondition(gate.pending?.id == second.id, "Rejecting stale input must preserve the current request")
        precondition(gate.consume(second.id), "The displayed current request may be explicitly confirmed")
        precondition(!gate.consume(second.id), "Double clicking must not send a second confirmation")
        let cancelled = gate.request("111111")
        gate.clear()
        precondition(!gate.consume(cancelled.id), "A cancelled attempt must not remain confirmable")
        let passkey = gate.request("222222", mode: .enterOnPhone)
        precondition(!gate.consume(passkey.id), "A passkey-entry notification must not become a yes/no approval")
        let repeated = gate.request("222222")
        precondition(!gate.consume(passkey.id), "Reused digits must not reuse a previous request identity")
        precondition(gate.consume(repeated.id))
        print("Pairing confirmation checks passed: explicit, single-use, current-request approval only.")
    }
}
