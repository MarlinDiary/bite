// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BiteKit",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "BiteKit", targets: ["BiteKit"]),
    ],
    targets: [
        .target(name: "BiteKit"),
        .testTarget(name: "BiteKitTests", dependencies: ["BiteKit"]),
    ]
)
