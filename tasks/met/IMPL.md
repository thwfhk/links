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
the locks and active rigid type variables. It preserves restrictions.
See [item 3.7](#37-explicit-binders) for source signature checking.
`Fresco.prepare_recursive` gives unannotated recursive definitions
monomorphic parameter and result types before checking any body. An
explicit result quantifier comes from the signature. Generalisation
follows checking the whole group and leaves variables shared with
frozen definitions monomorphic.

`FrescoPatterns` passes modal dependencies to matched and projected
fields and checks uses of linear values. Updating or extending a
closed modal record carries its dependencies on the inherited fields.
An open modal row must be usable in the current context before
extension. The initial implementation required unrestricted list
elements. Range syntax calls a fixed pure `intRange` primitive.
Explicit `intRange` calls still use lexical lookup.

At the end of milestone 3, `Frontend.Modal` exposed the new checker
for source-level tests and preserved binding contexts across successive
sentences. Those tests checked linearity within each program or sentence.
[Milestone 5 integration](#5-compiler-and-library-integration) switched
the native driver and typed transforms to Fresco and added tracking of
linear uses across REPL sentences. The
[milestone 3 checks and handover](PLAN.md#milestone-3-checks) describe
the earlier state.

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
a runtime error or `exit`, it keeps the linear moves made by the
interrupted sentence and restores the previous compiler scope. A successful
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

The follow-up notes build on the review of `98d39ac8`. The
[specification](SPEC.md) records the language rules, and the
[plan](PLAN.md#milestones) records implementation status and checks.

### Milestone 2 follow-up

#### 2.6 Syntax

`core/parser.mly` gives operation signatures their own production for
interface members and parenthesised handler clause annotations. Both
positions accept explicit quantifiers. `Types.Base` returns a kind
mismatch if an operation signature reaches the kind check.

The list-element production accepts atomic and grouped types. The
unary arrow domain also accepts list and modal prefixes. Both type
printers use the same grouping check on the type they print, including
explicit `mu` binders and nested lists.

#### 2.7 Interface names and printing

The module resolver builds a map from each interface identity to its
[chosen source name](SPEC.md#effect-interfaces). Both type printers use
the map from the completed input when displaying a result. For frontend
errors, use the scope recorded at the source position for both sides
of the comparison.
The frontend discards those source scopes at the end of the pass.
When no visible name resolves to an interface, its display includes
the original path, an out-of-scope mark and its declaration number.
The number also distinguishes repeated loads from the same location.
It is local to the interpreter process and appears only in diagnostic
text.

The roundtrip checks use a shorter module path that still names the
old declaration after the original path is shadowed. Rechecking the
expression against the printed type verifies the identity. The
[interface environment work](#55-interface-environments) covers
source name scope across non-isolated file inputs and custom preludes,
and interface signatures in local modules.

#### 2.8 Shadowed type aliases

Each alias declaration has its own internal name. The source scopes
used for interface printing also record the visible names for aliases.
Both printers keep the original alias spelling when it still resolves
to the same declaration. They use another visible spelling if needed.

Before choosing type variable names or grouping types, the printers
expand aliases with no usable name. With `typename T = Int;
var x = (1 : T); typename T = Bool;`, `x` prints as `1 : Int`.
If expansion exposes an interface with no name, the existing
[interface marker](#27-interface-names-and-printing) identifies it.
An alias that remains in scope can name a type containing such an
interface. If its written arguments contain a name that is out of
scope, the printer tries the underlying type as well. This can remove
an argument that the alias body never uses.

For an expanded recursive alias, a repeated application with the same
arguments becomes a `mu` reference. Argument comparison allows renamed
binders. Printers stop after 64 extra unfoldings with changed arguments
in one expansion, or when a changed argument list exceeds the 256-node
limit. At that point they mark the remaining alias as out of scope.
These limits apply only to printing, and the marker is diagnostic text.

### Milestone 3 follow-up

#### 3.5 Recursive types

`Types.Abs` derives requirements from the fields of each recursive
definition using fresh formal parameters. It follows type, row and
presence arguments until the requirements stop changing. For row
arguments it tracks the labels supplied by enclosing rows. Both the
kind predicate and the narrowing pass use these requirements.

`FrescoTypes` checks each recursive prefix using the cycle information
from exposing its head. The guard check stops at the first data or
function constructor, including a variant below a modality.

#### 3.6 Base kinds

`Types.Base` rejects non-identity modalities. It shares alias exposure
with the unifier so adjacent modalities that cancel through an alias
are reduced before the `Base`, `Mono` and `MonoAbs` checks. Narrowing
skips interface arguments discarded by cancellation.

#### 3.7 Explicit binders

`DesugarTypeVariables` checks source signatures and aliases for unbound
type, row and presence variables. Both use the explicit binder check,
which rejects anonymous `%` holes before inference. A modality keeps
the surrounding type variable scope. Explicit universal binders are
scoped to their type. The migrated library signatures name previously
implicit row tails, and bodies that refer to those variables use
explicit type abstraction where needed.

#### 3.8 Lock access and freezing

`FrescoContext.access` checks the binding before Fresco instantiates it.
It keeps an absolute type and computes the residual for consecutive
leading modalities. A quantifier ends that modal prefix. Implicit and
explicit type application use the type obtained by access, as does
freezing a variable through grouping parentheses.

#### 3.9 Partial type information

`Fresco.Partial` collects argument types after lock access and uses the
callee's known domains to refine those types. It keeps known modalities
and quantifiers when following curried applications and pattern
binders. A residual supplied by a lock alone leaves an unsolved type
variable open. `FrescoTypes` uses known types of frozen arguments for
consistency checks, then prefers the expected result type to convertible
argument hints. If the body can be absolute, full checking uses
later type information to settle any interface argument constraints.
`FrescoTypes` also compares the modal hints for a quantified argument.
It requests an annotation when neither a fixed type nor the expected
type resolves competing hints. See [item 3.13](#313-argument-types-before-instantiation).
Polymorphic `do` calls use the same frozen argument hints when choosing
the operation's own type arguments.

Handler clause inference is tracked in [item 4.6](#46-handler-result-types).

#### 3.10 Value restriction

Fresco checks the value restriction when it introduces a modal or
universal prefix. Branches and the final expression of an effectful
block may return an existing prefixed type. A handler clause can return
a value checked at the clause's expected type. A forwarding return
keeps the type obtained from the handled computation. `TypeSugar` uses the
checked binding pattern and type to decide whether matching can fail.
For a variant pattern the type must have a closed row with the named
tag as its sole possible alternative. The body of a type abstraction
is checked with its bound variables in scope, and lowering keeps
computations inside the same quantifier scope.

#### 3.11 Record and comprehension typing

Fresco and the IR checker apply the same unrestricted-tail check for
record upcasts. Both compare function arguments by position after
checking their count. They compare arguments from target to source
and the result from source to target.

`FrescoPatterns.unprefix` supplies the wrapper used to carry the
[leading binders](SPEC.md#modal-record-extension) onto inherited field
types. Lowering instantiates the base with its own type variables before
projecting each inherited field and binds those variables again on
each field. It evaluates the base once before the new fields.
List comprehensions check their body against the known list type.
The regressions run with frontend rechecking and strict IR checking.
See [item 5.7](#57-record-and-comprehension-lowering) for integration.

#### 3.12 Absolute field presences

Implemented in `d48a31fb`. `FrescoPatterns.record_fields` keeps the
same unknown presence when its kind already requires `Abs` and the
closed record has been instantiated. A record with its own leading
quantifier needs instantiation first so its binders stay in scope
and lowering receives a record row. `Fresco.record_fields` still
converts an open record as a whole.

See the [extension rule](SPEC.md#modal-record-extension) and the
[milestone checks](PLAN.md#milestone-312-checks). See
[3.11](#311-record-and-comprehension-typing) for quantified records.

#### 3.13 Argument types before instantiation

Partial inference records where a frozen field or a fixed call result
constrains an argument type. A frozen field guides the type at its
position in the aggregate. If a surrounding modality changes the field's
context, full checking determines its type there. When the callee's
type fixes a bare result, inference rules out a fresh leading modality
while leaving the result's component types open. A call such as
`id(1)` can still use its expected modality to choose a type argument.

#### 3.14 Expected types in conditional branches

Both branches receive the expected result type and the permission to
introduce a prefix from their enclosing check. Each branch applies the
value restriction to its own expression. The signed recursive example
can introduce the result quantifier on its base-case lambda. Its
recursive call returns a function with that quantifier already in its
type.

### Milestone 4 follow-up

See the [follow-up checks](PLAN.md#milestone-4-follow-up-checks)
and [design checks](PLAN.md#milestone-4-design-checks).

#### 4.5 Shared interface arguments

Partial inference collects separate observations from the handled
expression and from resumption calls. It tracks local bindings and the
position of the installed interface occurrence through nested handlers
and modal locks. A `do` call uses the newest occurrence. A function's
required context can also constrain an older occurrence.

`infer_interface_arguments` checks equality constraints and probes
conversions from supplied types to each candidate and from the
candidate to expected types. See the
[shared interface argument rule](SPEC.md#shared-interface-type-arguments)
and [incompatible arguments](#413-incompatible-shared-interface-arguments).
Frontend rechecking uses the instance stored in the typed handler and
checks the clauses against its schemes.

#### 4.6 Handler result types

`Partial.handler_result` combines known types from return and operation
clauses. For a [forwarding return](SPEC.md#forwarding-returns), full
checking can try the combined type on the input. It falls back to
ordinary input inference if that check fails.

#### 4.7 Operation clause quantifier scope

The checker records source annotation occurrences and their enclosing
operation clauses before solving types. The rigid scope check protects
annotation variables shared outside a clause, along with its ambient
context, handler result and interface arguments. It checks each clause
result within the rigid scope.

#### 4.8 Linear use in handlers

One usage check covers all shallow clause alternatives, including the
inserted return. For deep clauses, the checker checks and removes
clause pattern bindings before it checks uses of state bindings. This
distinguishes state use from a shadowing binder. Other deep-clause
captures require unrestricted types. State initialisers contribute
their uses in sequence.

#### 4.9 Relative prefixes on absolute results

`branch_results` implements the
[branch agreement rule](SPEC.md#first-class-polymorphism-and-modal-types)
for inferred `if`, `switch` and handler results. It compares all branch
bodies before testing whether the common type is absolute. This lets a
later branch determine whether the leading relative prefixes can be
dropped.

#### 4.11 Redundant annotations on forwarding returns

For expected-type propagation, compare the annotation with the
partially inferred return binding type before applying the expected
type. For full clause checking, compare it with the checked binding
type. A matching ordinary annotation preserves forwarding. Leading
modalities and quantifiers remain explicit, and ordinary annotations
can still remove a modality or instantiate a quantifier.

#### 4.12 Forwarding switch returns

`identity_return` follows the forms listed under
[forwarding returns](SPEC.md#forwarding-returns). For each switch
branch it removes names bound by the pattern from the tracked aliases
before adding any aliases for the whole scrutinee.

#### 4.13 Incompatible shared interface arguments

When no observed candidate passes and the fallback comparison fails,
`infer_interface_arguments` compares closed monotypes after erasing
modalities to detect the conflict described in the
[shared interface argument rule](SPEC.md#shared-interface-type-arguments).

### Milestone 5 follow-up

#### 5.5 Interface environments

The compiler context carries the source name scope. Isolated inputs
start with the prelude scope. Non-isolated inputs and successful REPL
commands carry that scope forward. Each file checks its own duplicate
operation names. `ModuleScope` is shared by the dependency loader and
resolver. Imported declarations are compiled once per input. This
step exposed imported names in the scope that requested them. The
[reviewed import rules](SPEC.md#module-imports) restore outer-scope
visibility for external modules.

Datatype desugaring keeps interface signatures by declaration identity
through blocks, recursive definitions and frontend rechecks. Leaving a
block restores its lexical names and aliases. Failed inputs keep the
previous context and registry.

#### 5.7 Record and comprehension lowering

Item [3.11](#311-record-and-comprehension-typing) supplies the lowering
for the checked record and comprehension types. `ListElements` carries
the generator list's modality to its element type for frontend
rechecking. Lowering erases it and keeps the original list value.
The combined checks in
[PLAN.md](PLAN.md#milestones-56-follow-up-checks) cover those types,
explicit instantiation before extension under `Presence(Abs)`, and
function arity checks for upcasts.

#### 5.8 Linear lists

`Types.Unl` checks and constrains the list element type. `Nil`, `Cons`
and `Concat` admit `a::Any`; list consumers such as `hd` and `tl` and
the comprehension helpers still require unrestricted elements.

`core/compilePatterns.ml` emits an IR `ListCase` for binding and case
patterns. It gives the cons branch both the head and tail and knows the
result of an earlier split when trying a later alternative. The original
list remains available to alternatives that bind the whole value. The
native list representation is unchanged.

#### 5.9 REPL recovery

`bin/driver.ml` observes reads of existing linear bindings in
`core/evalir.ml`. REPL lowering records these reads at the source
evaluation points, including reads when operands and closures are
evaluated. After an interruption, the REPL retains the consumption of
the bindings that were read and restores the preceding compiler scope.

The evaluator reports early exit separately from an ordinary return.
The REPL prints its value without the enclosing expression's type and
discards the new definitions. This step covered REPL commands and
`@load`. See the [native `exit` signature](SPEC.md#native-effects) and
the [reviewed rule for file arguments](SPEC.md#exit-from-a-file).

#### 5.10 State helpers

The state computations and callbacks stay pure. `fmap` applies its
callback inside the state computation. `sequence` builds its list there
and threads state from left to right. Both return values directly.
`return` requires `Abs` on the argument it captures.

#### 5.11 SAT failure

`leftBiased` and `parse` use `Maybe` within their handlers to choose
whether to try another branch. After the handler finishes, an absent
result signals `Fail` to the caller. `parseTextExpression` uses `maybe`
to handle this failure. The parser retains its backtracking diagnostic.

#### 5.12 Standard comprehension helpers

The driver loads `lib/comprehension.links` before the selected prelude
and skips user preprocessing for those bundled definitions.
`core/desugarFors.ml` gives its definitions private names and uses those
names for generated calls. This makes the same helpers available with
an empty or custom prelude. Explicit calls use ordinary lexical lookup.
The generated calls carry their type arguments through frontend rechecking.

#### 5.13 Custom comparisons

`core/fresco.ml` checks that each custom comparison returns `Bool`.
Typing and lowering use the same resolved binding at the call site.
Only a call to the built-in primitive can use its `ApplyPure` flag.
A scoped comparison uses the standard precedence when it has no
fixity declaration of its own.

#### 5.14 Quantified record and tuple patterns

Record projections and patterns apply the record's type arguments
before reading a field or removing fields. They abstract over the same
arguments afterwards. Tuple patterns use numbered fields in the same
code. Switch alternatives rebuild their rest records under those
quantifiers. Constant patterns instantiate the field for the comparison
and keep the quantified type for any binder.

#### 5.15 REPL evaluation order

REPL lowering leaves native operand computations in their ordinary
places. When a later operand has separate IR bindings, lowering marks
earlier linear moves for recovery if those bindings interrupt evaluation.
If the bindings finish, the interpreter clears the marks and observes
reads during ordinary operand evaluation. Named function declarations
record captures at the declaration. A function literal records its
captures when its value is evaluated, including when it occurs in an
earlier operand interrupted by a later one.

#### 5.16 Linear uses in generator sources

Fresco checks free uses in each source after the first against the outer
scope and requires their types to be unrestricted. It keeps all source
uses in the comprehension's usage count, so a nested comprehension
also reports its free uses to the enclosing check.

#### 5.17 Generator scope

The module resolver and typed frontend passes visit the generator
sources before binding any generator patterns. The patterns extend a
scope shared by the body, filter and sort keys. The lowering used for
the generator sources still nests the same list callbacks.

#### 5.18 Negative variant aliases

The default branch of a negative pattern receives the variant type with
the excluded tags removed. Bind aliases and apply annotations in that
branch. If an earlier test gave the exact tag, reconstruct the variant
from its payload at the alias's type. A later clause can test the
original variant with its own set of tags. The scrutinee is evaluated
once before the tests.
Comprehension lowering uses the source patterns directly in the body
and sorting callbacks. The separate callbacks that build the list of
generator combinations bind full values in their own patterns.

#### 5.19 List and variant patterns in quantified fields

List and variant matches inspect the body of the scrutinee's quantified
type. Lowering carries those quantifiers onto the head and tail of a
list and onto the payload and remaining variant in each branch. The
strict IR checker checks the same binder types. When an earlier match
establishes a variant's tag, lowering rebuilds the variant from its
payload under a type abstraction. It applies only the outer type
arguments, so any quantifiers on the payload itself are preserved.
Failed matches keep the original value and the parts already matched
available to later cases. The evaluator still dispatches on the stored
value.

#### 5.20 Enclosing aliases of negative patterns

Lowering binds an enclosing alias and checks its annotation after the
nested pattern succeeds. It rebuilds variant payloads and record or
tuple fields from the values available in that branch. Record rest
aliases use the fields left after the preceding parts of the pattern.
The type arguments of the original value still apply to these parts.

Switch lowering keeps the original scrutinee available on fallthrough.
Values proved by earlier tests are eligible for an alias at the type
the source checker assigned to that alias. Direct bindings keep the
original test order and share the initial value when rebuilding a
record. A whole-list alias keeps the original element type. Matches
inside a list element can still narrow that element's own aliases.

#### 5.21 Transitive import visibility

The module resolver adds each external module to the input scope as
it resolves that module's declarations. The next dependency and the
input's own declarations use that scope. Only a module's declarations
are recorded as its members. `open` and `open import` still affect
unqualified lookup in the current scope. The loader supplies one copy
of each dependency per input, so all references in that input share
its interface and operation identities.

#### 5.22 Import initialisation order

The loader visits imports in written order and lists each module after
its dependencies. The regression checks both orders of two independent
imports that share a dependency, then checks their effects occur before
the input's own initialiser.

#### 5.23 Constructing the SAT thunk

The first arrow of `leftBiased` uses the empty effect context. Its
callback has the absolute type `[Choice, Failure] (() -> a)`, which can
cross the returned function's `[Failure]` lock. Only calling that
function enters the handler and can signal the final `Fail`.

### Deferred optimisation issues

Dead-definition elimination can remove unused calls to `crypt`, `chr`
and `verify` because their primitive definitions use the `PURE` flag.
`crypt` can use `wild`, and `chr(-1)` and `verify("bad", "pw")` can
raise. Keep these cases for testing when work on `--optimise` resumes.

Inlining can move a linear read past an error in the REPL. For example,
in `{ var g = f; error("fail"); g(41) }`, moving the read of `f` to
the call to `g` changes whether the interrupted command used up `f`.
Dead-definition elimination can also remove the unit bindings that
mark earlier moves for REPL recovery.
