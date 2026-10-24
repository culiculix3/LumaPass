// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumaPass",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "LumaPassCore", targets: ["LumaPassCore"])
    ],
    targets: [
        .target(name: "LumaPassCore"),
        .testTarget(name: "LumaPassCoreTests", dependencies: ["LumaPassCore"])
    ]
)
