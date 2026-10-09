// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BiteKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "BiteKit", targets: ["BiteKit"]),
        .library(name: "BiteCommands", targets: ["BiteCommands"]),
    ],
    targets: [
        // Its resources: the pages Bite opens with, and the colours' and the to-do widget's words,
        // in each language Bite speaks.
        .target(name: "BiteKit", resources: [.process("Resources")]),
        .testTarget(name: "BiteKitTests", dependencies: ["BiteKit"]),
        // What Bite's command line tool does, and its MCP server for AI apps.
        .target(name: "BiteCommands", dependencies: ["BiteKit"]),
        .testTarget(name: "BiteCommandsTests", dependencies: ["BiteCommands"]),
    ]
)
