import SwiftUI

struct AppPanelView: View {
    let panel: AppPanel
    let model: ReceiverModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(panel.title).font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch panel {
                    case .diagnostics:
                        Text(model.status).font(.headline)
                        Text(model.detail).foregroundStyle(.secondary)
                        if let error = model.error { Text(error).foregroundStyle(.orange) }
                        Text("These details stay on your Mac. Review them before sharing.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(model.diagnostics.isEmpty ? "No connection activity yet." : model.diagnostics)
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    case .help:
                        Label("Prepare this Mac", systemImage: "1.circle").font(.headline)
                        Text("Choose Set up DashLink and review the experimental connection notice. Internet access is needed for this first step.")
                        Label("Choose your iPhone", systemImage: "2.circle").font(.headline)
                        Text("Open Settings → Bluetooth on your unlocked iPhone. Choose Find iPhones in DashLink, then select your phone.")
                        Label("Connect", systemImage: "3.circle").font(.headline)
                        Text("Join the same Wi-Fi on both devices. Enter that network’s name and password, then choose Connect iPhone. Confirm matching pairing codes on both devices if asked, and allow CarPlay on your iPhone.")
                        Text("Click the CarPlay screen to navigate. Sound starts automatically when supported. Display, audio, and keyboard controls are under More beneath the viewer.")
                        Text("If connection fails, unlock your iPhone, check that both devices are on the same Wi-Fi, and try connecting again. Use Connection details to inspect the error.")
                    case .about:
                        Text("DashLink \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.headline)
                        Text("A wireless CarPlay receiver for your Mac.")
                        Text("Test release for Apple silicon Macs running macOS 15 or later. This build is locally signed, not notarized by Apple. It is not an Apple-certified CarPlay accessory.")
                        Text("The connection uses a shared experimental accessory identity prepared locally. It may stop working after an iOS update. No connection identity, Wi-Fi password, or personal phone data is included in the shared app.")
                        Text("Your Wi-Fi password is used only for the current session. Connection records and logs stay in Application Support/DashLink on your Mac. Nothing is uploaded for analytics.")
                        Link("PlayPort · open-source receiver", destination: URL(string: "https://github.com/youcci/playport")!)
                        Link("Experimental identity provenance", destination: URL(string: "https://github.com/shihabal3amri/DiPlay/blob/main/docs/THIRD_PARTY_NOTICES.md")!)
                        Text("GPL-3.0 · Source code and third-party notices accompany this release. CarPlay is a trademark of Apple Inc. DashLink is not affiliated with Apple.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28).frame(width: 570, height: 510)
    }
}
