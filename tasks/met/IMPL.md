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
During milestone 2, the row-based checker still served the native
entry points. Milestone 5 switched them to Fresco.

Both type printers emit the approved `MonoAbs` shorthand. The parser
separates adjacent modality brackets at a type boundary and preserves
symbolic term operators such as `<|>` and `><`.

Milestone 3 exposed modal prefixes hidden by aliases, applied declared
restrictions to explicit type arguments and bound range syntax to the
standard pure helper. The [baseline and milestone checks](PLAN.md#status)
and [migration inventory](MIGRATION.md) record the verified cases.

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
extension. The initial implementation required unrestricted list
elements. Range syntax calls a fixed pure `intRange` primitive.
Explicit `intRange` calls still use lexical lookup.

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
one member use the same rigid quantifier identities. Lowering uses the
checked operation schemes to build the IR handler.

The top-level context supplies `wild`. The primitive signatures
are in [`core/lib.ml`](../../core/lib.ml). The lowering flag
`ApplyPure` serves a separate purpose. See the
[native rules](SPEC.md#native-effects) and
[milestone 4 checks](PLAN.md#milestone-4-checks).

### Milestone 4 follow-up

The following fixes are planned against source revision `98d39ac8`.
They use the existing interpreter examples from the review as
regressions. The [plan](PLAN.md#4-type-operations-handlers-and-native-effects)
records the checks.

1. `Partial.handler_hints` considers a limited set of expression
   forms. `annotated_resume_argument` recognises a direct annotated
   resumption argument. For `Reader(a::Abs)`, moving an annotated
   absolute function from `k`'s argument into a local binding can
   hide its type. A `switch` can hide the same information from a
   `do` call. Collect known types in their own scope and use them
   before fixing the interface arguments. Keep the change in effect
   context at nested handlers and modal introductions.
2. `FrescoTypes.merge_known` currently prefers the first of two
   conflicting type hints. Reordering `do Put(1)` and
   `do Put(2 : [] Int)` can change the inferred type of `do Get`
   from `Int` to `[] Int`. Check constraints for the shared
   interface argument together. Request an annotation when they
   still leave more than one choice.
3. `Partial.infer` reads handler return branches and leaves out
   operation bodies. Full checking also gives a syntactic identity
   return special access to the expected result type. Use known
   types from both kinds of clause. Cover a polymorphic `do Fail`
   with an aborting clause returning a function annotated
   `[](() -> Int)`. The result should type-check with an implicit
   return. Also cover an explicit return that binds the returned
   value to another name before returning it.
4. The rigid scope check currently protects every source
   annotation. Keep the protection for a shared `%t` used both
   inside and outside the clause. Permit a `%t` used only in the
   clause to refer to that clause's rigid type, with checks that
   the type cannot escape through the result or shared arguments.
5. Return and operation clauses currently have separate usage
   counts which are added together. This rejects a shallow handler
   that uses a captured linear value once in each clause. Align all
   shallow clauses as alternatives, including the inserted return
   clause. Change the one-group fixture to cover use in every branch
   and rejection when the return branch omits the use. In deep
   clauses, check state binders as local values, with the ordinary
   once-per-branch check for linear values. A clause binder that
   shadows a state binding cannot supply its use. Keep the
   unrestricted check for other captured values and count uses in
   state initialisers sequentially.
6. Inferred handler results can drop a relative modality when the
   common body is known to be absolute. The ordinary branch check
   in `same_branches` can reject the same pair of types. Share the
   absolute result rule across conditionals, switches and handlers.
7. `crypt` currently has a `[wild]` signature and keeps the old
   `PURE` lowering flag. The optimiser can erase an unused call.
   Lower it as an ordinary application and make the regression
   check that its evaluation survives optimisation.

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

## Follow-up review

The cases below come from the review of `98d39ac8`. The approved
language rules are in [SPEC.md](SPEC.md). Implementation and its
completion checks are pending in [PLAN.md](PLAN.md#milestones).

1. **Syntax (2.6).** `core/parser.mly` uses the general datatype grammar
   for `=>` and accepts list and modal prefixes as bare list elements.
   Give operation signatures their own grammar while keeping quantified
   handler clause annotations. Supplying `() => Int` to a type alias
   with a `Base` parameter reaches an internal error in `core/types.ml`.
   Reject it in the parser and make `Types.Base` reject an operation
   signature normally if one reaches the kind check. Use a list-element
   production for atomic or grouped types. Check both printers and the
   migrated library and example types.
2. **Names and printing (2.7).** `core/desugarModules.ml` already binds
   interface names in declaration order, and `core/chaser.ml` loads
   imports once per dependency pass. A later REPL import can load a new
   module with the same printed name. `core/modalEffects.ml` prints
   the path stored at declaration time, which can name a newer interface
   after shadowing. Give both printers the name scope and use a short or
   qualified name only when it resolves to the same declaration. Mark
   declarations with no visible name as out of scope. Use one naming
   context for both sides of a diagnostic and distinguish repeated loads
   from the same location. Compare declaration identities in the
   print-and-reparse test.
3. **Recursive types and kinds (3.5–3.6).** The recursive case in `core/types.ml`
   checks each alias argument when it sees an alias again. For
   `typename Box(a) = (|Done:[] a|More:Box(a)|);`, the only callback
   field is absolute. The current check rejects `Box(Int -> Int)` as
   an operation payload. Derive `Abs` requirements from the fields, with
   absolute modalities already satisfying the requirement. Combine the
   requirements across the recursive group, substituting arguments until
   the requirements stop changing. Track fields that row substitution can
   replace, and use the same requirements to check and narrow kinds.
   Test `Box` recursing as `Box(List a)` and
   `typename Shift(a,b) = (|Here:a|More:Shift(b,Int -> Int)|);`.
   The first case must terminate and accept `Box(Int -> Int)`. The
   second must reject `Shift(Int,Int)` as an operation payload.

   Separately, `core/frescoTypes.ml` can visit
   the same `mu` binder twice while exposing a modal prefix and report
   a cycle for `(Leaf : [] (mu a. (|Leaf|More:a|)))`. Stop the guard
   check at the variant constructor.

   For `Base`, a kind check in
   `core/frescoTypes.ml` accepts a `Base` variable as a monotype,
   but `core/unify.ml` rejects modal types as monotypes. The case
   `typename M(a::MonoAbs) = a; typename B(b::Base) = M(b);` accepts
   `B([] Int)` and rejects `M([] Int)`. Make `Base` reject `Modal`
   and remove the case that narrows the body of a modal type to `Base`.
   Both aliases should reject `[] Int` and accept `Int`.
4. **Explicit binders (3.7).** `core/desugarTypeVariables.ml` allows
   implicit binders based on the outer node of a signature. A leading
   `[]` can hide a `forall`, so a misspelt type variable can be bound
   implicitly. Check every source `sig` and `unsafe sig` for unbound
   type, row and presence variables. Use named binders for row tails
   that the signature used to quantify implicitly, such as the key
   row in `sortByBase`. Check anonymous holes such as the `%` in
   `sig f : forall a. (a, %) -> a`, which currently adds a second
   quantifier. Keep explicit binders scoped to their type.
   Migrate the signatures that relied on implicit variables in the
   body using the existing explicit type abstraction where needed.
5. **Lock access and freezing (3.8).** `Fresco.variable` can
   instantiate a variable before checking access. `FrescoContext.access`
   also looks under `ForAll` and can move quantifiers in its fallback.
   Apply Maetel's access rule first, including its absolute-type case.
   Apply explicit type arguments to the type obtained by access. Test
   binding an explicitly applied value outside a lock. Replace the
   unit tests that expect instantiation before access or transport
   through a quantifier. Make `~((f))` behave like `~f`.
6. **Partial type information (3.9).** The checker can reject
   `same(~ident, ident)` while accepting `same(ident, ~ident)` for
   `fun same(x,y) { [x,y] }`. The existing `app(poly)(~id)` test
   also passes with freezing where reference case A12 uses `app(poly)(id)`.
   Preserve known types from all the arguments, expected types and
   modal pattern binders before solving. A conversion of `<Reader(a)> Int`
   to `<Reader(b)> Int` already holds by `Abs`; the partial pass must
   leave the interface arguments alone in this case. Keep the approved
   rule of asking for an annotation if later constraints leave a choice.
7. **Value restriction (3.10).** In `core/fresco.ml`, `adapt` can open
   an expected quantifier after ordinary checking has bypassed the
   value check. `(print("once") : forall a. ())` is accepted. An
   effectful block ending in a lambda can also receive an expected
   quantified result. Check eligibility where a prefix is introduced,
   while allowing computations to return values that already have
   such a type. In `core/typeSugar.ml`, the variant pattern cases
   assume assignments always match. Use the checked pattern and type
   when deciding eligibility. Keep the runtime match failure where the
   binding is allowed. Test eligible checked literals, including an
   empty list at `forall a. List a`, and reject escaping type variables.
8. **Data checking and lowering (3.11 and 5.7).** Preserve inherited
   quantifiers when projecting or extending a record. Check the
   expected element type in a list comprehension and keep its modality
   or quantifiers through frontend rechecking. The record upcast in
   `core/fresco.ml` checks named fields it omits, but can drop an open
   tail without checking its linearity. Check that a discarded tail
   is unrestricted. Test an upcast from `(n:Int | r)` to `(n:Int)`
   with `r::Row(Any,Any)` containing a linear callback.
   Duplicate update fields are already rejected by
   `check_field_names`. See
   [upcasts and record updates](SPEC.md#upcasts-and-record-updates).
9. **Modal record extension (3.12).** `Fresco.record_fields` converts
   an open record as a whole. `FrescoPatterns.record_fields` carries a
   prefix on a closed record one field at a time. It keeps an unknown
   presence when its kind already requires `Abs`. A record with its own
   leading quantifier needs instantiation first, so its binders stay in
   scope and lowering receives a record row. See the
   [extension rule](SPEC.md#modal-record-extension).
10. **Interface environments (5.5).** `core/desugarDatatypes.ml` drops
    the signatures registered in a block. `core/chaser.ml` can also fail
    to recognise a module declared there. At the CLI boundary,
    `bin/links.ml` carries the values and types of the prelude and of
    non-isolated inputs, while `core/desugarModules.ml` keeps the name
    scope only in interactive mode. Carry source name scope with the
    compiler context and keep resolved signatures by declaration identity
    through blocks, recursive definitions, final expressions and frontend
    rechecks. Restore enclosing name and alias scopes on leaving a block.
    Follow the resolver's lexical module and `open` rules in dependency
    loading. Check duplicates per file. Start isolated inputs with the
    prelude scope and carry scope across non-isolated inputs and successful
    REPL inputs. Preserve the previous scope and registry on failure.
11. **Linear lists (5.8).** Allow linear elements in the list constructor
    and make `Types.Unl` check and constrain the element type. Apply the
    rule in type annotations, literals, cons, append and patterns. In
    `core/lib.ml`, allow `Nil`, `Cons` and `Concat` at `a::Any`. Keep
    unrestricted element bounds on native functions that can discard
    elements, including `hd` and `tl`, and on collection helpers that
    require them.

    `core/compilePatterns.ml` currently tests equality with `Nil` and
    calls `$$hd` and `$$tl` separately. Replace that lowering with a
    single internal split into the empty or cons case. Give the cons
    case both the head and tail. Use it for binding and case patterns,
    including nested patterns and later alternatives that bind the
    whole list. Test a fallback after a failed nested pattern and
    a list stored inside another linear value. Keep the native list
    representation.
