// swift-tools-version: 5.9
// CatBehavior — autonomous behaviour, locomotion and navigation for the companion character (technical evaluation).
// Swift standard library only: no Foundation, UIKit, SpriteKit or Spine imports, so the same source runs in the iOS
// app (Spine or SpriteKit renderer), in `swift test` on Linux/macOS and, compiled to WebAssembly, in the browser harness.
import PackageDescription

let package = Package(
    name: "CatBehavior",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CatBehavior", targets: ["CatBehavior"])
    ],
    targets: [
        .target(
            name: "CatBehavior",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "CatBehaviorTests",
            dependencies: ["CatBehavior"]
        )
    ]
)
