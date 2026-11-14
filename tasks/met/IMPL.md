# SmallLinks modal effect types implementation notes

The [specification](SPEC.md) contains the approved language design.
The [plan](PLAN.md) contains milestones, status and check results.

As each milestone proceeds, record significant implementation decisions
under its heading. Include the affected source, the reason for the
decision and any effect on the approved specification. Link to the plan's
checks. Keep language-design questions in SPEC.md until they are resolved.

## Implementation approach

Reuse existing Links code where it fits the new design, including its
monotype unification mechanisms. Restructure or rewrite code when that
significantly improves its structure and clarity. Record substantial
decisions here as implementation proceeds.

## 1. Reviewed design and baseline

The design review and [baseline checks](PLAN.md#implementation-baseline)
are complete. See the [migration inventory](MIGRATION.md) for the
affected signatures, tests and examples.

Removed `unsafe_cast` from the native primitive table in `core/lib.ml`.
Checked upcasts use IR coercions. `tests/native.tests` checks that the
primitive is unavailable.

## 2. Syntax, types and scoped contexts

The parser reads `List A` and `List(A)` through the same constructor.
`List` remains available as a term constructor. Both type printers
group compound list elements and print variant absences as `Label{-}`.
The parser shares the grammar for open-only record and variant rows
until their closing delimiter distinguishes them.

`ModalEffects` stores interface instances newest first for each
declaration. It stores `wild` separately and takes argument equality
from the caller. `Unify` checks the shape of two modalities before
unifying corresponding arguments. Relative transformations contract a
matching mask and extension at the binding context. A residual that
restores repeated interface instances starts after the occurrences
the requirement still masks. This preserves the type arguments in
`<Reader, Reader |>` followed by restoration to `<Reader |>`, where
the first two occurrences can have different arguments.

`DesugarModules` resolves effect interfaces and operations in their
own namespaces. Each declaration has an identity, including when two
modules use the same names. The operation registry maps the runtime
label back to that identity and the declared signature. A declaration
can refer to itself. Later declarations follow ordinary left-to-right
lookup. Failed REPL sentences and loads restore the prior name scope.

The front end registers operation signatures and checks declared kinds,
including absolute operation arguments and results. It lowers modal
syntax to `Types.Modal` and ambient arrows to `Types.AmbientFunction`.
`Abs` remains independent of value linearity. The restriction meet
represents `Mono` together with `Abs` as `MonoAbs` so both checks apply.
Legacy effect arrows still serve the active type checker. It reports a
type error for modal value annotations and uses of declared operations.

Both type printers emit the approved `MonoAbs` shorthand. The parser
separates adjacent modality brackets at a type boundary and preserves
symbolic term operators such as `<|>` and `><`.

Fresco must expose modal prefixes hidden by aliases when it compares
types or crosses locks. Milestone 3 also applies declared restrictions
to explicit type arguments and binds range syntax to the standard pure
helper. The [baseline and milestone checks](PLAN.md#status) and
[migration inventory](MIGRATION.md) record the verified cases.

## 3. Modal inference and polymorphism

`Fresco` checks resolved source in inference, checking and application
modes. Its partial pass uses copies of flexible variables and leaves
holes where a term supplies no type information. It reads annotations
and frozen types directly. Full checking passes the expected argument
types back to the terms and checks their bodies and uses of bindings.

`FrescoTypes` controls instantiation and kind checks. It collects
information about each quantified argument before substitution.
`Unify.consistent` compares known quantifiers, modalities and data
types, and restricts flexible type, row and presence variables to
monotypes. Explicit type application checks the declared kind and
preserves the surrounding modalities. Aliases preserve their
quantifiers in the modal frontend. Prefix traversal rejects a
recursive alias that repeats before reaching a type constructor.

`FrescoContext` retains a binding's effect context and the locks
between binding and use. It derives a residual for access across those
locks. Modality conversion can postpone the choice between an
absolute body and matching interface arguments. The solver settles
choices forced by later type information and requests an annotation
for remaining choices. It does not search combinations of unresolved
conversions. Type-variable changes and pending conversions roll back
on a failed check.

Generalisation excludes the term environment, the ambient context,
the locks and active rigid type variables. It preserves restrictions
and the existing quantification of implicit signature variables.
Unannotated recursive groups share monotypes while all bodies are
checked. Generalisation follows checking the whole group, and leaves
variables shared with frozen definitions monomorphic.

`FrescoPatterns` passes modal dependencies to matched and projected
fields and checks uses of linear values. Updating or extending a
closed modal record carries its dependencies on the inherited fields.
An open modal row must be usable in the current context before
extension. List elements must satisfy the built-in constructor's
unrestricted kind. Range syntax calls a fixed pure `intRange`
primitive. Explicit `intRange` calls still use lexical lookup.

`Frontend.Modal` exposes this checker for source-level tests and
preserves binding contexts across successive sentences. Tests check
linearity within a program or sentence. Integration must account for
reuse of a linear binding across sentences. The typed transforms and
native driver still use the row-based checker. See the
[milestone 3 checks and handover](PLAN.md#milestone-3-checks).

## 4. Operations, handlers and native effects

`Fresco` resolves each operation to its declaration and selects the
newest instance of that interface. The instance fixes the shared
arguments before member quantifiers are instantiated. A handler checks
coverage by declaration identity and installs one instance per interface.
The partial pass uses known type structure from calls, clause annotations
and patterns. Full checking verifies the arguments in scope. The checker
uses rigid member quantifiers in clauses and checks that those variables
cannot escape through the result, shared arguments or source annotations.

The handled computation has an extension lock. Return patterns carry
that dependency into fields and elements. An omitted return uses a
synthetic identity clause. Deep resumptions take the operation result
followed by the state arguments. Shallow resumptions carry the extension
and return the input computation's result. Each state initialiser uses
the enclosing scope. State binders are in scope for both kinds of clause.

The modal handler descriptor records the enclosing context, extension
and instantiated member schemes by resolved label. The alternatives of
one member use the same rigid quantifier identities. The legacy row
slots remain for the running compiler. The lowering work in 5.2 needs
the modal descriptor, the carried return type and the resolved labels.

`Frontend.Modal.initial_context` supplies the modal primitive types and
starts with `wild`. `Lib.modal_type_env` uses an explicit set of native
permissions independent of `ApplyPure`. It reuses the value types from
the legacy primitive table. The modal `exit` scheme requires an absolute
payload and instantiates its result separately. `error` raises a
deterministic runtime error and is pure. `sleep` retains its timing
permission while its implementation is pending. See the
[milestone 4 checks](PLAN.md#milestone-4-checks).

## 5. Compiler and library integration

The file, expression and REPL drivers now call Fresco. The parser and
surface type representation use ambient arrows and declared effect
interfaces. The old source checker was removed. Its value restriction
and variable usage counts are shared by the modal checker.

The primitive table gives native functions their modal signatures
directly and keeps the separate `ApplyPure` flag. The two preludes and
standard library use ambient callbacks where arguments and results
share the invocation context. The pure state helpers give stored state
functions a fixed context and require captured state values to be
absolute. The [migration inventory](MIGRATION.md) records the changes
to `Comp`, `gen0`–`gen2` and examples that used effect arguments.

Typed frontend passes carry the types of terms under modal
introductions and preserve the checked operation schemes. The optional
frontend recheck uses the incoming Fresco environment and rolls back
changes to compiler types after checking. The compiler erases modalities
from IR types after frontend checks. The IR checker verifies the
runtime types of operation calls, handler results, state and
resumptions. Runtime dispatch uses the resolved operation label, so a
module can declare an operation with the same source name as an
operation in another module.

The REPL retains the types and binding contexts from each successful
sentence. It also records whether a linear binding has been used. After
a runtime error, it marks the linear bindings already read by the
failed sentence and restores the previous compiler scope. A successful
file load or module definition also records the uses of linear bindings
it creates before exporting its environment.

## 6. Review and final verification

Separate reviews covered source checking and lowering. Changes from
the reviews preserve generator scope, known modal variant payloads
and quantified arguments under a modality. Frontend rechecking keeps
the rigid parameters of an already checked operation. IR checking
handles recursive data types, and the optimiser keeps handler-local
bindings and exported prelude definitions live where they are needed.

The [SmallLinks guide](../small/SPEC.md) describes the modal language.
The [verification record](PLAN.md#milestones-56-checks) records the
combined checks, and the [migration inventory](MIGRATION.md) links to
the deferred fixtures.
