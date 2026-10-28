import SwiftUI

struct SetupView: View {
    @Bindable var model: ReceiverModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Your iPhone. On your Mac.").font(.largeTitle.bold())
                    Text("Connect wirelessly to use CarPlay on a bigger screen.")
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 22) {
                    if !model.isPrepared {
                        preparation
                    } else {
                        phone
                        Divider()
                        network
                        connectionAction
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(28)
                .frame(maxWidth: 500, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: DashLinkStyle.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: DashLinkStyle.cornerRadius).strokeBorder(.quaternary))
                Text("Experimental receiver · No cable or extra hardware")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28).padding(.vertical, 32)
        }
        .background(.background.secondary)
    }

    private var preparation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("A quick first-time setup", systemImage: "sparkles").font(.headline)
            Text("Prepare the receiver on this Mac, then choose your iPhone and Wi-Fi network.")
                .foregroundStyle(.secondary)
            if model.isInstalling {
                ProgressView("Preparing your Mac…").controlSize(.small)
            } else {
                Button("Set up DashLink", action: model.requestExperiment)
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Text("This test release uses an experimental connection. Compatibility may change with iOS updates.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var phone: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("iPhone", systemImage: "iphone").font(.headline)
                Spacer()
                Button(model.isScanning ? "Searching…" : "Find iPhones", action: model.scan)
                    .disabled(model.isBusy)
            }
            if model.phones.isEmpty {
                Text("Unlock your iPhone and open Settings → Bluetooth, then choose Find iPhones.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Picker("Choose iPhone", selection: $model.selectedPhone) {
                    Text("Choose your iPhone").tag("")
                    ForEach(model.phones) { phone in Text(phone.displayName).tag(phone.id) }
                }
                .labelsHidden().frame(maxWidth: .infinity).disabled(model.isBusy)
                Text("Keep your iPhone nearby and unlocked. Pairing is handled when you connect.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var network: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wi-Fi", systemImage: "wifi").font(.headline)
            Text("Join the same Wi-Fi network on both devices.")
                .font(.subheadline).foregroundStyle(.secondary)
            TextField("Network name", text: $model.ssid)
                .textFieldStyle(.roundedBorder).disabled(model.isBusy)
                .accessibilityLabel("Wi-Fi network name")
            SecureField("Network password", text: $model.password)
                .textFieldStyle(.roundedBorder).disabled(model.isBusy)
                .accessibilityLabel("Wi-Fi password")
            Text("Your password stays in this session and is never saved.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var connectionAction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: model.connect) {
                Text(model.isPairing ? "Pairing…" : model.isCheckingBluetooth ? "Connecting…" : "Connect iPhone")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!model.canConnect)
            if model.isScanning || model.isPairing || model.isCheckingBluetooth {
                HStack(alignment: .top, spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}
