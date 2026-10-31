// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Lyrix",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Lyrix", targets: ["LyrixApp"]), .library(name: "LyrixCore", targets: ["LyrixCore"])],
    targets: [
        .target(name: "LyrixCore"),
        .executableTarget(name: "LyrixApp", dependencies: ["LyrixCore"]),
        .testTarget(name: "LyrixCoreTests", dependencies: ["LyrixCore"])
    ]
)
