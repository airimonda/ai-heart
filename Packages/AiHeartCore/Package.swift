// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AiHeartCore",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "AiHeartCore", targets: ["AiHeartCore"]),
    ],
    targets: [
        .target(name: "AiHeartCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "AiHeartCoreTests", dependencies: ["AiHeartCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
