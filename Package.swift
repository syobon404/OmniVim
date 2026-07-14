// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OmniVim",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OmniVim", targets: ["OmniVim"])
    ],
    targets: [
        .executableTarget(name: "OmniVim"),
        .testTarget(name: "OmniVimTests", dependencies: ["OmniVim"], resources: [.process("Fixtures")])
    ]
)
