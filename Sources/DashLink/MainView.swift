import SwiftUI

struct MainView: View {
    @Bindable var model: ReceiverModel
    @State private var panel: AppPanel?

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model, panel: $panel)
            Divider()
            if let url = model.viewerURL {
                CarPlayWebView(url: url)
            } else if model.isRunning || model.isStopping {
                ConnectionStatusView(model: model)
            } else {
                SetupView(model: model)
            }
        }
        .frame(minWidth: 820, minHeight: 620)
        .tint(DashLinkStyle.accent)
        .alert("Set up the experimental receiver?", isPresented: $model.showExperimentalChoice) {
            Button("Prepare connection", action: model.prepareExperiment)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("DashLink downloads DiPlay’s public preview and prepares its shared accessory identity on this Mac. This is not Apple-certified and may stop working after an iOS update. No identity is included in the app you share, and this step does not pair your iPhone.")
        }
        .sheet(item: $model.pairingRequest) { code in
            PairingView(code: code, model: model)
        }
        .sheet(item: $panel) { destination in
            AppPanelView(panel: destination, model: model)
        }
    }
}
