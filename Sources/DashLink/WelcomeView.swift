import SwiftUI

struct WelcomeView: View {
    let model: ReceiverModel
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 24)
            HStack(spacing: 20) {
                Image(systemName: "iphone").font(.largeTitle)
                Image(systemName: "wifi").font(.title2)
                Image(systemName: "laptopcomputer").font(.largeTitle)
            }
            .foregroundStyle(.tint).accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(model.status).font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text(model.detail).font(.title3).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            HStack(spacing: 24) {
                Label("Maps", systemImage: "map")
                Label("Music", systemImage: "music.note")
                Label("Siri", systemImage: "waveform")
            }
            .font(.subheadline).foregroundStyle(.secondary)
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline).foregroundStyle(.orange)
                    .padding(16).frame(maxWidth: 490)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 24)
            Text("Real CarPlay appears here after your iPhone accepts the connection.")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 30)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color.accentColor.opacity(0.07), Color.clear], startPoint: .topTrailing, endPoint: .bottomLeading))
    }
}
