#if os(macOS)
import Foundation
import Testing

private final class SyntaxBoundaryBundle: NSObject {}

@Suite private struct SyntaxBoundaries {
    @Test func extensionMacroCannotIntroduceConformanceOnAnExtension() throws {
        let diagnostic = try rejected("""
            import ComposableArchitecture2
            struct Domain {}
            @ComposableArchitecture2.Feature
            extension Domain {}
            """)
        #expect(diagnostic.contains("macro cannot be attached to extension"))
    }

    @Test func importedFeatureMacrosRequireDisambiguation() throws {
        let diagnostic = try rejected("""
            import ComposableArchitecture2
            import Interface_ComposableArchitecture
            struct Domain {}
            @Feature
            extension Domain: FeatureProtocol {
                var body: some Feature { EmptyFeature() }
            }
            """)
        #expect(diagnostic.contains("ambiguous use of 'Feature"))
    }

    @Test func featureOnlyOpaqueResultDoesNotExposeEditingCapability() throws {
        let diagnostic = try rejected("""
            import ComposableArchitecture2
            import Interface_ComposableArchitecture
            func erase<P: Lens>(_ value: Editing<P>) -> some FeatureProtocol<Editing<P>.State, Never> { value }
            func consume<P: Lens>(_ value: some Editor<P>) {}
            func check<P: Lens>(_ value: Editing<P>) { consume(erase(value)) }
            """)
        #expect(diagnostic.contains("conform to 'Editor'"))
    }

    @Test func viewInputsRejectHiddenPropertyWrapperSemantics() throws {
        let diagnostic = try rejected("""
            import Interface_ComposableArchitecture
            import SwiftUI
            @View struct WrappedInput {
                @AppStorage("count") var count: Int = 0
            }
            """)
        #expect(diagnostic.contains("@View supports @Binding inputs and @State/@FocusState local storage"))
    }

    @Test func viewLocalStateMustBePrivate() throws {
        let diagnostic = try rejected("""
            import Interface_ComposableArchitecture
            import SwiftUI
            @View struct SharedState {
                @State var count = 0
                var body: some SwiftUI.View { Text("Count") }
            }
            """)
        #expect(diagnostic.contains("@View local state must be private"))
    }

    @Test func viewInputsRejectCompetingInitializers() throws {
        let diagnostic = try rejected("""
            import Interface_ComposableArchitecture
            @View struct CustomInput {
                let count: Int
                init(count: Int) { self.count = count }
            }
            """)
        #expect(diagnostic.contains("@View derives the input initializer"))
    }

    /// Uses the modules and plugins produced by this workspace's build, not a
    /// separately resolved package graph or a developer's global module cache.
    private func rejected(_ source: String) throws -> String {
        var products = Bundle(for: SyntaxBoundaryBundle.self).bundleURL
        while !FileManager.default.fileExists(atPath: products.appendingPathComponent("Interface_ComposableArchitecture.swiftmodule").path) {
            let parent = products.deletingLastPathComponent()
            products = try #require(parent != products ? parent : nil)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("Boundary.swift")
        try source.write(to: fixture, atomically: true, encoding: .utf8)
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        #if arch(arm64)
        let target = "arm64-apple-macos27.0"
        #else
        let target = "x86_64-apple-macos27.0"
        #endif
        let build = products.deletingLastPathComponent().deletingLastPathComponent()
        let map = build.appendingPathComponent("Intermediates.noindex/GeneratedModuleMaps/ComposableArchitecture2RuntimeShims.modulemap")
        process.arguments = [
            "swiftc", "-typecheck", "-swift-version", "6", "-target", target,
            "-enable-upcoming-feature", "MemberImportVisibility", "-warnings-as-errors",
            "-I", products.path, "-I", products.appendingPathComponent("Modules").path,
            "-F", products.appendingPathComponent("PackageFrameworks").path,
            "-Xcc", "-fmodule-map-file=\(map.path)",
        ] + [
            "ComposableArchitecture2Macros#ComposableArchitecture2Macros",
            "Interface Composition Macro Plugin#Interface_Composition_Macro_Plugin",
            "DebugSnapshotsMacros#DebugSnapshotsMacros",
            "CasePathsMacros#CasePathsMacros",
        ].flatMap { ["-Xfrontend", "-load-plugin-executable", "-Xfrontend", products.appendingPathComponent($0).path] }
            + [fixture.path]
        process.standardError = output
        try process.run()
        let diagnostic = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus != 0, "The proposed boundary is not a compiler limitation; simplify the syntax")
        #expect(!diagnostic.contains("no such module") && !diagnostic.contains("missing required module"), "\(diagnostic)")
        return diagnostic
    }
}
#endif
