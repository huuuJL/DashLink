import SwiftUI

struct ConnectionStatusView: View {
    let model: ReceiverModel
    var body: some View {
        VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text(model.status).font(.title2.bold())
            Text(model.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.secondary)
    }
}
