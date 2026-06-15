// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftRIP",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "SwiftRIP", targets: ["SwiftRIP"])
    ],
    targets: [
        .target(name: "SwiftRIP"),
        .testTarget(name: "SwiftRIPTests", dependencies: ["SwiftRIP"])
    ]
)
