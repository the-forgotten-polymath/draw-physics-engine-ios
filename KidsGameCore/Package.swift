// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "KidsGameCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KidsGameCore", targets: ["KidsGameCore"])
    ],
    targets: [
        .target(name: "KidsGameCore"),
        .testTarget(name: "KidsGameCoreTests", dependencies: ["KidsGameCore"])
    ]
)
