# Domain-first feature interpretation

`@Interface` owns canonical child coordinates, primary operation metadata, calls,
embeddings and optics. Its output contains no TCA dependency and no second model
of the domain. The bridge consumes that output instead of parsing imported domain
syntax or importing another package's macro Core.

A source extension declares its interpretation:

```swift
@Interface_ComposableArchitecture.Feature
extension Domain: FeatureProtocol {
    public var body: some Feature {
        Features {
            Child(\.read)
            Child(\.commands)
        }
    }
}
```

`Child` selects a direct domain coordinate with the parent's lifetime. `Presenting`
selects an optional child. `Observing(self)` follows the distinguished operation's
stream. `Requesting(self)` composes and submits its canonical request. The syntax
contains no operation symbols, structural descriptors, state/action aliases or task
identifiers. Each existing child receives its own source interpretation.

The composition macro derives one state product and one routed action sum. The
public domain aliases refer to that implementation. It attaches TCA's `@Feature`
to a generated member, letting TCA derive observation, case paths, scopes and other
runtime witnesses. Generated declarations state the needed conformances inline,
so no witness depends on lowering an extension macro nested inside extension output.
The implementation delegates behavior to the source body; there is no parallel
state or independently executed copy of the composition.

Child selection matches key paths, not the child type name. Two same-typed children
therefore retain independent state, task/error ownership and lifetimes. Scoped-store
projections hold the original store reference. Observation has no actions of its own;
its result and request remain the canonical operation's types.

## Editing and listing

`@EditingPolicy` attaches to an extension containing an editing property:

```swift
@EditingPolicy
extension Domain {
    public var editing: some EditingFeature {
        Editing(
            create: create,
            update: update,
            delete: delete,
            draft: \.draft,
            blank: .discardNewDeleteExisting(\.isBlank),
            ignoreUpdateFailure: Update.Error.notFound
        )
    }
}
```

The macro derives a `DraftProjection` coordinate and a nested `EditingFeature`
capability alias. The record itself adopts no bridge marker. Editing state can be
initialized with an original record or a draft, and replacement through the selected
writable key path preserves identity and complementary fields. Lens laws remain the
responsibility of the chosen projection; blank/error policies are not algebraic laws.

`Listing(self, rows: \.rows, commands: Domain.self, editing: \.editing,
deleting: \.delete?.id)` selects a result projection and an opaque editing capability.
The result adopts no marker conformance either. Listing observes the original result,
overlays current edits on its rows, and composes editing without downcasting an opaque
feature. Request fields forward to the existing request storage.

`Editing(in: Domain.self, \.editing)` reuses that exact editing state and policy in
another existing domain type. Commands and editing resolve from the actual lexical
interface instance supplied by the composition. Standalone descendants require
`.interface(domain)`. No global dependency or manufactured instance is consulted.

## Calls, policy and runtime boundaries

Property sending uses the canonical embeddings. Required children route their calls
through their own interpretation; explicit `.call(...)` selects the root lifetime.
`InterfaceCalls.interfaceCall` forgets the route only for matching domain policy.
The original action still executes exactly once in its original scope.

`.dismiss(\.page, matching: \.filter.list, before: \.lists?.delete?.id)` clears only
a matching presentation before execution. It neither executes nor reroutes the call.
An error stays on its original task; dismissal is not rolled back. This policy is an
explicit relationship, not something inferred from names or operation types.

TCA's actionless scopes use the unique injection from Never and do not require a
CasePathable parent. TCA's declared action scopes take precedence where both routes
could be inferred. Canonical domain calls therefore need no consumer marker adoption.
The optional CallPaths adapter remains available to clients explicitly using TCA case
key paths on canonical calls; the generic interpretations do not require it.

## Source/compiler requirements

- Source extensions retain explicit FeatureProtocol conformance. An extension macro
  cannot attach to an extension to add that conformance, nor extend unrelated children.
- Qualify the bridge's Feature macro when importing TCA's macro of the same name.
- An opaque `some Feature` hides editing-specific capabilities. Use the generated
  `some EditingFeature` alias for the separately declared policy.
- Untyped throws supplies no enum context for a bare failure case. Name the domain
  error value explicitly; only matching update errors are ignored. Other errors propagate.
- Canonical case projections are partial, so composed deletion paths use optional chaining.
- The bridge re-exports its Operation algebra because generated public signatures expose
  its canonical types and conformances under hard MemberImportVisibility checking.

The descriptor-based `@FeatureComposition` remains supported for explicit initial
values and lower-level interpretation selection. It shares the composition derivation
with the body-based macro. Neither entry point invents domain operations or copies
another macro's derivation algorithms.

## SwiftUI input and presentation interpretation

`@View(Domain.self)` on a view struct injects an existing `StoreOf<Domain>` and
constructs the product of that store and explicitly declared value inputs. `@View`
without a domain constructs value/closure inputs only. It does not generate a View
body, choose controls, or create a feature. The caller supplies the store; no global
store lookup or duplicate state is introduced. Custom property wrappers on inputs
and handwritten initializers are diagnosed rather than guessed.

The injected store's projected value provides ordinary field bindings and composes
required/presented child coordinates already selected by `@Feature`:

```swift
@View(Domain.self)
public struct Screen {}

extension Screen: SwiftUI.View {
    public var body: some SwiftUI.View {
        NavigationStack {
            // ...
        }
        .sheet(item: $store.children.form) { form in
            FormView(store: form)
        }
    }
}
```

`ViewStore` and `ViewBindings` adapt an existing store reference. The generated
`Bindings` coordinate map delegates to TCA's bindable scopes. Assigning nil ends the
installed presentation; receiving a child store does not create another lifetime.
The ordinary writable-field fallback remains available for form drafts.

`EditingRows(store) { record in ... } editor: { store in ... }` interprets Listing's
existing row identity and selected draft. It replaces the edited row's renderer and
renders an unsaved draft once after the rows. Both rendering closures remain explicit.
The reusable `.focusOnPresentation()` modifier owns field focus as a local UI policy;
it does not run requests or commit edits. Feature dismissal remains responsible for
commit semantics.
