// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TodoTarget",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TodoTargetCore", targets: ["TodoTargetCore"]),
        .executable(name: "TodoTarget", targets: ["TodoTarget"]),
    ],
    targets: [
        .target(name: "TodoTargetCore"),
        .executableTarget(name: "TodoTarget", dependencies: ["TodoTargetCore"]),
        .testTarget(name: "TodoTargetCoreTests", dependencies: ["TodoTargetCore"]),
    ]
)
