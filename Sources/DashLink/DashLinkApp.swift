import SwiftUI

@main
struct DashLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = ReceiverModel()

    var body: some Scene {
        Window("DashLink", id: "main") {
            MainView(model: model)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1100, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
