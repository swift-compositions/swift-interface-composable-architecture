import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct Plugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [Composition.self, Feature.self, Editor.self, View.self]
}
