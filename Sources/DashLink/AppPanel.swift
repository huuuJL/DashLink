import Foundation

enum AppPanel: String, Identifiable {
    case diagnostics, help, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .diagnostics: "Connection details"
        case .help: "Getting started"
        case .about: "About DashLink"
        }
    }
}
