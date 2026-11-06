// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BalliKit",
    platforms: [.iOS(.v18), .macOS(.v14), .watchOS(.v11)],
    products: [.library(name: "BalliKit", targets: ["BalliKit"])],
    targets: [
        .target(name: "BalliKit", resources: [.process("Resources")]),
        .testTarget(name: "BalliKitTests", dependencies: ["BalliKit"]),
    ],
    swiftLanguageModes: [.v5]
)
