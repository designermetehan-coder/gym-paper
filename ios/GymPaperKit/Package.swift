// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GymPaperKit",
    platforms: [.iOS(.v18), .macOS(.v14), .watchOS(.v11)],
    products: [.library(name: "GymPaperKit", targets: ["GymPaperKit"])],
    targets: [
        .target(name: "GymPaperKit", resources: [.process("Resources")]),
        .testTarget(name: "GymPaperKitTests", dependencies: ["GymPaperKit"]),
    ],
    swiftLanguageModes: [.v5]
)
