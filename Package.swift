// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-interface-composable-architecture",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "Interface ComposableArchitecture", targets: ["Interface ComposableArchitecture"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/TCA26.git", branch: "main", traits: ["Dependencies", "Clocks"]),
        .package(url: "https://github.com/swift-atoms/swift-operation.git", branch: "main"),
        .package(url: "https://github.com/swift-molecules/swift-interface.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Interface ComposableArchitecture",
            dependencies: [
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Operation", package: "swift-operation"),
            ]
        ),
        .testTarget(
            name: "Interface ComposableArchitecture Tests",
            dependencies: [
                .product(name: "ComposableArchitectureTestSupport", package: "TCA26"),
                "Interface ComposableArchitecture",
                .product(name: "Interface Macro", package: "swift-interface"),
            ],
            swiftSettings: [.enableExperimentalFeature("Lifetimes")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]
}
