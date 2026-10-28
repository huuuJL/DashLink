// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DashLink",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "DashLink", targets: ["DashLink"])],
    targets: [.executableTarget(name: "DashLink", linkerSettings: [.linkedFramework("IOBluetooth"), .linkedFramework("Network")])]
)
