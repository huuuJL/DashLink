import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: ReceiverModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}
