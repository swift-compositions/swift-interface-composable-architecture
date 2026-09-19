// swift-tools-version: 6.4

import CompilerPluginSupport
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
        .package(url: "https://github.com/pointfreeco/swift-debug-snapshots", from: "0.4.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "603.0.2"..<"604.0.0"),
        .package(url: "https://github.com/pointfreeco/TCA26.git", branch: "main", traits: ["Dependencies", "Clocks"]),
        .package(url: "https://github.com/swift-atoms/swift-operation.git", branch: "main"),
        .package(url: "https://github.com/swift-molecules/swift-interface.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-optic.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-either.git", branch: "main"),
        .package(url: "https://github.com/pointfreeco/swift-case-paths", branch: "protocol-case-paths"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    ],
    targets: [
        .macro(
            name: "Interface Composition Macro Plugin",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Interface ComposableArchitecture",
            dependencies: [
                "Interface Composition Macro Plugin",
                .product(name: "Interface Macro", package: "swift-interface"),
                .product(name: "CasePaths", package: "swift-case-paths"),
                .product(name: "ComposableArchitecture2", package: "TCA26"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "Either", package: "swift-either"),
                .product(name: "Operation", package: "swift-operation"),
                .product(name: "Optic", package: "swift-optic"),
            ]
        ),
        .testTarget(
            name: "Interface ComposableArchitecture Tests",
            dependencies: [
                .product(name: "ComposableArchitectureTestSupport", package: "TCA26"),
                .product(name: "DebugSnapshots", package: "swift-debug-snapshots"),
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

// Integration consumers enforce import visibility at the compilation boundary.
for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
}
