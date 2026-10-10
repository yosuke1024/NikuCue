// swift-tools-version: 5.9
// NikuCueDomain — pure Swift domain logic for NikuCue.
// Foundation only. No UI, SpriteKit, SwiftData, StoreKit or advertising imports (docs/06 §2).
import PackageDescription

let package = Package(
    name: "NikuCueDomain",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NikuCueDomain", targets: ["NikuCueDomain"])
    ],
    targets: [
        .target(
            name: "NikuCueDomain",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "NikuCueDomainTests",
            dependencies: ["NikuCueDomain"]
        )
    ]
)
