# Interface composition

`@Interface` describes capabilities and emits `Structure` member descriptors. Each
descriptor has an `Owner`, the original child `Value`, and its canonical key path.
There is no TCA dependency in that representation, no copied operation model, and
no attempt to discover imported declarations through another macro's Core.

`@FeatureComposition` attaches to a source extension conforming the existing type
to `FeatureProtocol`. It selects interpretations of those descriptors:

```swift
@FeatureComposition(
    .required(Domain.Structure.read.self),
    .presented(Domain.Structure.create.self),
    calls: Domain.Call.self
)
extension Domain: FeatureProtocol {}
```

Required children compose by products of states and sums of routed actions.
Presented children add an optional state, not a second operation signature.
`.observing(Domain.Run.self)` selects the existing `Observing` interpretation; its
`Never` action contributes no route. Initial requests and required states can be
supplied with `initial:`. Omitted initial values require a valid empty initializer.
Presentation starts absent and receives its input when opened. Multiple simultaneous
instances must be modeled explicitly; optional presentation does not infer collection
identity, navigation policy, or a choice of screen.

For a custom root policy, put the annotated empty extension and the conformance
with its custom `body` in separate source extensions. An annotated extension that
declares `FeatureProtocol` receives the default body; an extension without that
conformance declaration derives only the composition. This separation avoids Swift
6.4's circular macro lookup while resolving a source body's inherited builder.
The custom body composes its policy with `composition`, without declaring State or Action.

The generated `_Composition` is an implementation detail and the sole owner of its
state storage and routed action sum. `Domain.State`, `.Action`, and `.Scopes` alias
that output. The macro attaches TCA's `@Feature` to a member declaration so that
TCA owns observation, case paths, scopes, and runtime machinery. Generated feature,
state, and action declarations state their conformances directly. Their witnesses
still come from the attached TCA macros; no conformance depends on a nested macro
extension being lowered. It does not invoke TCA macro implementation APIs.
It never extends a type other than the source type being interpreted.

A selected child must already conform to `FeatureProtocol`. Leaf integrations can
alias `Observing`, `Requesting`, `Listing`, or `Editing` state without re-declaring
it. Source extensions are necessary: a root extension macro cannot extend arbitrary
imported child types under Swift 6.4's macro rules.

`calls:` selects execution of canonical domain calls in this composition's task
lifetime. Child routes retain their own execution, error, and dismissal lifetimes.
They cannot all be collapsed into the root Call without changing semantics.
Canonical property sending uses `Calls.route`: required children interpret their own
calls when their Action supports that call family, using the existing case prisms.
The remaining calls enter `.call`. An explicit `store.send(.call(...))` still chooses
the root lifetime. This distinction is encoded in generated routing, independent
of which dynamic-member overload Swift selects for property navigation.

Required children have scoped-store projections: `store.lists` refers to the child
store, and `store.lists.delete(id)` uses that child's canonical sender. Access through
`store.state` remains an ordinary domain-shaped state value. Optional child state
is writable on its scoped parent; bindings use that parent's existing TCA scopes.
The projection holds the store reference, never a copy or parallel state structure.

Compositions publish their owner through `InterfaceContext<Owner>` in the feature
environment. `WithInterface` lets a descendant interpret an explicit relationship
requiring an ancestor's capabilities (for example, a query page editing records).
The nearest enclosing owner wins. A standalone descendant must receive its owner
with `.interface(owner)`; there is no global fallback or second implementation.

Deleting a list closes its page, blank drafts are discarded, and successful forms
dismiss because the application chooses those policies, not because product/sum
algebra can infer them. Task storage is supplied by the TCA interpretation.
