import SwiftUI

struct PairingView: View {
    let code: PairingCode
    let model: ReceiverModel
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
            Text(code.mode == .compare ? "Check the code on your iPhone" : "Enter this code on your iPhone").font(.title2.bold())
            Text(code.value).font(.system(.largeTitle, design: .monospaced).bold())
                .textSelection(.enabled)
            Text(code.mode == .compare ? "Continue only if this code matches the one on your selected iPhone. Confirm Pair on the iPhone too." : "Enter this code on your selected iPhone when it asks. DashLink is waiting for pairing to finish.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel, action: model.cancelPairing)
                if code.mode == .compare {
                    Button("The codes match") { model.confirmPairing(requestID: code.id) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(34).frame(width: 440)
        .interactiveDismissDisabled()
    }
}
