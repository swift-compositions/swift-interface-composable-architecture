import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct Plugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [CompositionMacro.self, DomainFeatureMacro.self, EditingPolicyMacro.self, ViewMacro.self]
}
