import Foundation
import IOBluetooth

enum BluetoothCallback: Sendable {
    case found(Phone)
    case inquiryEnded(Int32, Bool)
    case pairingStarted
    case pairingConnected
    case confirmation(String, ObjectIdentifier)
    case passkey(String)
    case legacyPIN
    case simplePairingEnded(UInt8)
    case pairingEnded(Int32)
    case connectionEnded(Int32)
    case servicesEnded(Int32)
    case channelOpened(Int32)
    case received(Data)
    case channelClosed
}

/// Legacy callbacks can arrive on any thread. Only immutable values cross into
/// the main actor; Bluetooth objects stay owned by NativeBluetoothClient.
final class BluetoothDelegateAdapter: NSObject, IOBluetoothDeviceInquiryDelegate,
    IOBluetoothDevicePairDelegate, IOBluetoothDeviceAsyncCallbacks, IOBluetoothRFCOMMChannelDelegate {
    let deliver: @Sendable (BluetoothCallback, Bool) -> Void

    init(deliver: @escaping @Sendable (BluetoothCallback, Bool) -> Void) { self.deliver = deliver }

    private func emit(_ event: BluetoothCallback) { deliver(event, Thread.isMainThread) }

    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        guard let address = device.addressString, !address.isEmpty else { return }
        let marker = device.isPaired() ? " [paired]" : " [new]"
        emit(.found(Phone(id: address.uppercased().replacingOccurrences(of: "-", with: ":"),
                          name: (device.name ?? "Bluetooth device") + marker)))
    }
    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        emit(.inquiryEnded(error, aborted))
    }
    func devicePairingStarted(_ sender: Any!) { emit(.pairingStarted) }
    func devicePairingConnected(_ sender: Any!) { emit(.pairingConnected) }
    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        guard let sender = sender as? IOBluetoothDevicePair else { return }
        emit(.confirmation(String(format: "%06u", numericValue), ObjectIdentifier(sender)))
    }
    func devicePairingUserPasskeyNotification(_ sender: Any!, passkey: BluetoothPasskey) {
        emit(.passkey(String(format: "%06u", passkey)))
    }
    func devicePairingPINCodeRequest(_ sender: Any!) { emit(.legacyPIN) }
    func deviceSimplePairingComplete(_ sender: Any!, status: BluetoothHCIEventStatus) {
        emit(.simplePairingEnded(status))
    }
    func devicePairingFinished(_ sender: Any!, error: IOReturn) { emit(.pairingEnded(error)) }
    func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) { }
    func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) { emit(.connectionEnded(status)) }
    func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) { emit(.servicesEnded(status)) }
    func rfcommChannelOpenComplete(_ sender: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        emit(.channelOpened(error))
    }
    func rfcommChannelData(_ sender: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int) {
        guard let pointer, length > 0 else { return }
        emit(.received(Data(bytes: pointer, count: length)))
    }
    func rfcommChannelClosed(_ sender: IOBluetoothRFCOMMChannel!) { emit(.channelClosed) }
}
