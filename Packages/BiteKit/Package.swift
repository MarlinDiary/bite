// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BiteKit",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "BiteKit", targets: ["BiteKit"]),
        .library(name: "BiteCommands", targets: ["BiteCommands"]),
    ],
    targets: [
        .target(name: "BiteKit"),
        .testTarget(name: "BiteKitTests", dependencies: ["BiteKit"]),
        // What Bite's command line tool does, and its MCP server for AI apps.
        .target(name: "BiteCommands", dependencies: ["BiteKit"]),
        .testTarget(name: "BiteCommandsTests", dependencies: ["BiteCommands"]),
    ]
)
