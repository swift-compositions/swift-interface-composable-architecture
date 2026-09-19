# swift-interface-composable-architecture

Reusable TCA interpretations of the canonical operation algebra emitted by `@Interface`.
The domain and macro packages do not depend on TCA. This package consumes their existing
symbols, inputs, outputs, and calls instead of defining another domain representation.

| Interpretation | State and behavior |
| --- | --- |
| `InterfaceFeature<Call>` | Executes any eligible interface's canonical calls on `writes`. No bespoke feature or action enum is needed. |
| `Executing<Symbol>` | Edits the canonical Input, executes on demand, and retains the typed last successful Output. Failures live on `execution`. |
| `Observing<Symbol>` | Follows the sequence returned for a request; a changed request cancels and replaces observation. |
| `Requesting<Symbol>` | Composes the canonical Input, submits canonical Calls on `sending`, and dismisses on success. A requesting store's `send()` submits its current request. |
| `Editing<Record>` | Uses a writable draft projection and supplied create/update/delete arrows. Commits the final draft on dismount. Blank handling and ignored update errors are explicit policies. |
| `Listing<Symbol, Call>` | Composes observation, canonical command dispatch, row projection, draft overlay, and optional editing. The domain supplies the delete-event projection. |

```swift
let commands = Reminders.Call.feature(reminders)
let execution = Reminders.Create.Run.executing(reminders.create)
let observation = Reminders.Read.Run.observing(reminders.read)
let submission = Reminders.Lists.Create.Run.requesting(reminders.lists.create)
```

`Symbol` is an existing `Operation.Operable` or `Operation.Composed` symbol. The `.feature`,
`.executing`, `.observing`, and `.requesting` factories are constrained interpretations of
that algebra, not new symbols. Using one explicitly selects its lifecycle policy.

The `.calling(owner, id:)` modifier interprets an Action that is itself a Call.
`.calling(\.call, owner, id:)` interprets the selected Call case of a larger action enum.
The existing `Calls` witness and `Operation.Sending` embeddings preserve property syntax
such as `store.update.complete(id, true)` in both forms.

## Relationships and policy

`EditableRecord` supplies a writable `draft` witness. Assignment must preserve identity
and complementary fields, and obey the lens get-put, put-get, and put-put laws. The
protocol is a contract; Swift does not prove those equations. `ListingValue` supplies a
row projection from the domain's original query result, without replacing that result.

The editor's default policy saves blank values. `.discardNewDeleteExisting` selects the
alternative explicitly. An ignored update failure never suppresses create or delete
failures. `commit(_:)` exposes the same editing policy independently of its UI lifecycle.

TCA's `@FeatureExtension` can derive attributes and scopes on an explicit source extension
when a domain deliberately chooses a direct `FeatureProtocol` conformance. It requires a
State struct and body, can reuse the default Action derivation, and adds no stored feature
properties to the domain. Generic Listing and Editing instances own their store machinery.
A domain may instead use generic interpretations without any FeatureProtocol conformance.

## Boundaries

These features require Copyable state values. The operation algebra itself supports a
wider ownership model; these interpreters do not pretend that TCA state supports it all.
The runtime `Operation.Operable.run` contract throws `any Error`; the concrete error is
retained in the task outcome, rather than being presented as a statically indexed Failure.

An arbitrary operation signature does not determine initial inputs, field editors,
rendering, navigation, or commit policies. Those require reusable witnesses or explicit
application choices. This package supplies executable feature interpretations, not an
inferred UI schema or proof of application-specific business laws.
