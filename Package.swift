// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Prunese",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Prunese", targets: ["Prunese"])],
    targets: [.executableTarget(name: "Prunese")]
)
