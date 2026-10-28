import WebKit

@MainActor
final class WebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    var loadedURL: URL?

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let target = navigationAction.request.url,
              target.scheme == "http", target.host == "127.0.0.1", target.port == 18741 else { return .cancel }
        return .allow
    }

    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        guard origin.host == "127.0.0.1", origin.port == 18741, type == .microphone else { return .deny }
        return .prompt
    }
}
