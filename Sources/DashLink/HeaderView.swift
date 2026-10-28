import SwiftUI

struct HeaderView: View {
    let model: ReceiverModel
    @Binding var panel: AppPanel?

    var body: some View {
        HStack(spacing: DashLinkStyle.spacing) {
            Image(systemName: "car.side.fill")
                .font(.title2).foregroundStyle(.tint).accessibilityHidden(true)
            Text("DashLink").font(.headline)
            Text("TEST RELEASE").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if model.isRunning {
                Label(model.isConnected ? "Connected" : "Connecting…",
                      systemImage: model.isConnected ? "checkmark.circle.fill" : "wifi")
                    .foregroundStyle(model.isConnected ? DashLinkStyle.accent : Color.secondary)
                    .font(.subheadline)
                Button(model.isStopping ? "Disconnecting…" : "Disconnect", action: model.stop)
                    .disabled(model.isStopping)
            }
            Menu("More", systemImage: "ellipsis.circle") {
                Button("Connection details", systemImage: "stethoscope") { panel = .diagnostics }
                Button("Getting started", systemImage: "questionmark.circle") { panel = .help }
                Divider()
                Button("About DashLink", systemImage: "info.circle") { panel = .about }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .disabled(model.isPairing)
        }
        .padding(.horizontal, DashLinkStyle.padding)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
