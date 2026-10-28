import Foundation

@main struct PairingStateCheck {
    @MainActor static func main() {
        let model = ReceiverModel()
        model.isPrepared = true
        model.ssid = "test-network"
        let phone = Phone.parse("AA:BB:CC:DD:EE:FF My iPhone [paired]")!
        model.phones = [phone]
        model.selectedPhone = phone.id
        precondition(phone.displayName == "My iPhone (saved on Mac)")
        precondition(model.selectedPhoneHasPairing, "A saved pairing must be reusable without pairing again")
        precondition(!model.canStart, "A saved pairing alone does not prove an working CarPlay channel")
        precondition(model.canConnect, "Connect must be available for a known phone before the automatic channel check")
        model.verifiedBluetoothPhone = phone.id
        precondition(model.canStart)
        model.phones = [Phone(id: phone.id, name: "My iPhone [new]")]
        precondition(!model.canStart, "A newly discovered phone must pair first")
        model.pairedPhone = phone.id
        precondition(model.canStart)
        model.selectedPhone = "00:11:22:33:44:55"
        precondition(!model.canStart, "Changing phones must require that phone to pair")
        model.selectedPhone = phone.id
        model.isPairing = true
        precondition(!model.canConnect, "The one-step connect action must not overlap pairing")
        precondition(!model.canStart, "Pairing in progress must not enable CarPlay")
        model.isPairing = false
        model.isCheckingBluetooth = true
        precondition(!model.canConnect, "The one-step connect action must not overlap verification")
        precondition(!model.canStart, "A connection check in progress must block a concurrent start")
        model.isCheckingBluetooth = false
        model.verifiedBluetoothPhone = ""
        precondition(!model.canStart, "A failed channel check must block CarPlay")
        model.pairedPhone = ""
        precondition(!model.canStart, "An unsuccessful pairing must not enable CarPlay")
        print("Pairing state checks passed: saved pairings are reusable, working CarPlay channel verification is required for the selected phone, and concurrent operations block CarPlay.")
    }
}
