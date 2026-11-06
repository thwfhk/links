# Modal effects design

## Document role

The [specification](modal-effects-spec.md) defines the intended language:
syntax, typing, inference, runtime behaviour and compatibility changes.
This document records concrete implementation decisions, their reasons,
source comparisons and internal invariants. [PLAN.md](../PLAN.md) tracks
progress, dependencies, completion checks and the next action.

The specification owns language behaviour. Keep compiler APIs, representation
choices and algorithm details here. Keep status and verification logs in the
plan. Follow [AGENTS.md](../AGENTS.md) for the working procedure.

## Sources

- Wenhao's thesis, including modal effects and Fresco type inference:
  `~/code/latex/phd-thesis`.
- Aghilas' implementation of modal effects with Fresco:
  `~/code/type/frost/paper/artifact/freso-implementation`.
- Secondary reference, when needed: Aghilas' implementation with
  DK-style bidirectional type inference:
  `~/code/algebraic-effects/aghilas-met-impl`.
- Links syntax and parsing: `core/sugartypes.ml`, `core/lexer.mll`,
  and `core/parser.mly`.
- Links types and inference: `core/types.ml`, `core/typeSugar.ml`,
  `core/unify.ml`, `core/generalise.ml`, and `core/instantiate.ml`.
- Links effect processing: `core/desugarEffects.ml`,
  `core/desugarTypeVariables.ml`, and `core/sugartoir.ml`.
- Existing examples and tests in `examples/handlers/` and `tests/`.

Repository paths above are relative to the Links repository root.
As sources are examined, record the file paths, sections, and relevant
definitions supporting each design choice.

## Source comparison

Source inspection on 6 November 2026 identified the following rules
and implementation points. The comparison and executable probes below
form the basis for the implementation tasks.

### Thesis

Paths are relative to `~/code/latex/phd-thesis`.

- `chapters/met/met-calculus.tex`: core Met, ambient effect contexts,
  absolute and relative modalities, and static and dynamic semantics.
- `chapters/met/extensions.tex`: extensions including masks and
  polymorphism. Select the rules that apply without presence types.
- `chapters/metx/metx-calculus.tex`, definition "Scoped Rows":
  repeated operation labels are allowed; distinct labels may be
  reordered. This supplies the scoped row definition without adding
  explicit effect variables to the current scope.
- `chapters/maetel/type-system.tex`: Fresco's declarative type system,
  freezing, skeletons, and ghosts.
- `chapters/maetel/algorithm.tex`: algorithmic inference, skeleton
  inference, consistency, subtyping, constraint collection, and solving.
- `chapters/maetel/maetel.tex`: the extension of Fresco to first-class
  modal types, including implicit introduction, elimination, and
  modal instantiation, plus elaboration into Met.

### Combined Met/Fresco implementation

Paths are relative to
`~/code/type/frost/paper/artifact/freso-implementation`.

- `lib/syntax.ml`: `STMod`, `SMAbs`, and `SMRel` for surface types;
  `TMod`, `MAbs`, and `MRel` for internal types and modalities;
  effect contexts represented as lists; `Ghost`, `UGhost`, and `MFlex`
  for inference. Declarations group operations into named effects.
- `lib/effects.ml`: label lookup and removal, extension, modality
  application and composition, and right residuals. These functions
  preserve repeated labels. Ignore its `eff_ho` extension and restricted
  exchange rules; the selected scope contains ordinary named effects only.
- `lib/context.ml`: contexts containing variable bindings, type
  variables, locks, markers, and unknown type variables.
- `lib/type.ml`: `finfer` and `sk_infer` implement type and skeleton
  inference; `join_sk`, `join_var`, and `assign` implement consistency;
  `sub` and `sub_flex` implement subtyping. `look`, `constr_collect_sub`,
  `constr_collect_eq`, `solve_eq`, `solve_sub`, and `constr_solve`
  implement the associated constraint operations.
- `lib/parser.mly`: absolute `[E]`, relative `<D>` and `<L | D>`
  modalities, masking, and freezing syntax.
- `tests/fresco/pass/` and `tests/fresco/fail/`: polymorphism tests;
  `tests/pass/` and `tests/fail/`: modal effects and combined examples.
  Adapt examples to Links and check their expected outcomes against
  the selected thesis rules.

### Links

- `core/types.ml`: `Function` and `Lolli` carry effect rows;
  `Effect`, `Record`, and `Variant` share the row representation;
  field specifications include `Present` and `Absent`.
- `core/typeSugar.ml`: the typing context stores `effect_row`;
  inference calls `Unify`, `Generalise`, and `Instantiate`.

The shared row representation requires separating effect handling
from record and variant handling. The implementation map below
records the affected traversals and compiler passes.

## Language decisions and their reasons

The complete rules are in the specification. These decisions explain how
Links syntax and the references determine the implementation.

### Surface syntax

Keep the `modal` prefix as an explicit marker for modal types; bare angle
brackets enter XML syntax. Enter a separate lexer delimiter mode after
`modal`, independent of the `case` operation-pattern chevron counter. A modality
binds to a primary type so its arrow and quantified payload boundaries are
explicit. General freezing uses `freeze(e)` because `{| e |}` already means
page placement in Links; preserve `~x` for variables.

Modal annotations belong to binders. Preserve `::Any` as the existing ordinary
Links kind while also recording modal kind `Any`. Keep ordinary and modal kind
metadata separate through all syntax traversals.

### List types and handled-effect delimiters

Parse `List A` as the existing list datatype node. Keep the internal element
kind, list constructor and runtime representation. Update both type printers
in `core/types.ml` to emit prefix list types with the necessary parentheses.
Cover nested lists, function/modal/quantified element types, and parse/print
round trips. Preserve expression/pattern list syntax while migrating type
annotations, built-in type strings and expected type output. Migration includes
`core/lib.ml`, `prelude.links`, standard-library signatures and in-scope examples.

Use `<E>` after `handle` and `shallowhandle` for the optional handled-effect
annotation. Enter a suitable lexer mode after those keywords so angle brackets
remain independent of XML and the operation-pattern chevron counter. The mode
must also allow an unannotated handler followed directly by `(`. Preserve effect
names/type arguments, source positions, handler parameters and existing resolution
rules. Test qualified effects, parameterised effects, nested handlers and XML
inside the computation and clauses. Check the generated grammar for conflicts.

### Reference choices

Use Aghilas' named declarations to group operations while using the thesis'
scoped rows for effects. Omit the reference's higher-order effect extension.
Preserve Links' record/variant rows, explicit type abstraction/application,
handler parameters and shallow handlers.

Follow Fresco's local lets without implicit generalisation and require signed
recursion. These rules replace the old inference behaviour, so migration must
supply missing polymorphic and recursive signatures. The specification gives
the resulting source requirements.

Use the thesis for flexible modal-kind refinement and quantified-type modal
classification, as selected by the user on 6 November 2026. The latter rule
is in `chapters/met/extensions.tex`, the kinding rule and explanation for
polymorphism: classify the quantified body with value-type binders at `Abs`.
Consequently `forall a::Any. a` is absolute. This replaces Aghilas' classification
under the declared modal kinds.

Use temporary classifier bindings for this rule. Preserve ordinary kinds and
leave declared modal kinds unchanged for well-formedness, term checking,
instantiation and exported binder metadata. Row/presence binders receive no
new absolute-payload guarantee. Add positive and negative tests separating
quantified-type classification from actual instantiation requirements.

Require complete handler groups so dynamic selection agrees with consuming
one scoped-row occurrence. Preserve return-only Links handlers explicitly;
the reference's non-empty group assumption fails for them. Shallow resumption
typing follows `met/extensions.tex`, rule `ShallowHandle`, including its modal
context and computation result type.

### Scoped-row algorithms

Use a polymorphic row module whose payload can be shared types or skeletons.
Keep structural row operations pure. Match repeated occurrences left-to-right,
then solve the returned argument pairs. Equality consumes the full target;
subeffecting permits unmatched target entries. Failed comparisons must not
retain partial assignments. Relative mask equality uses multisets and preserves
multiplicity; printing preserves the supplied order.

Composition applies its first modality before its second, following
`effects.ml:compose`. Cancellation and right residuals account for repeated
labels. The type-level removal operations remain necessary without a term mask.

For relative lock `m = <L1 | D1>`, guard `n = <L2 | D2>`, and ambient
row `F`, compute `G = remove L2 F` and `K = L1 - L2`. Take the shortest
prefix `P` of `G` containing all occurrences requested by `K`. Let `Q`
be that prefix after removing `K`. Return
`<labels(D1) ++ (L2 - L1) ++ labels(Q) | D2 ++ P>`.
When `K` is empty, both prefixes are empty. Fail if `G` lacks a
requested occurrence. Absolute cases follow the reference.

Extraction must skip occurrences already removed by the guard, and
restoration preserves the supplied order of entries. A successful result
`r` satisfies `apply r (apply m F) = apply n F` in literal row order.
The normalised removal masks of `compose m r` and `n` also agree.
The construction supplies a sufficient crossing modality. Failure
means this construction has no result. The reference's transformation
relation does not in general admit a principal residual for arbitrary
removal masks: at empty `F`, lock and guard `<A>` admit both identity
and `<A,A | A>` as incomparable remaining modalities. Keep this
limitation explicit when implementing variable access.

## Type inference

Use Fresco's three modes: inference, checking against a type, and
function mode carrying an argument skeleton and the remaining mode.
In an application, infer the argument skeleton in `Check Ghost`, infer
the function in function mode, then check the argument against the
resulting domain. Full inference must perform the variable lock check
even when skeleton inference already visited that variable.

| Rule group | Thesis section in `maetel/algorithm.tex` | Reference functions |
|---|---|---|
| Type inference | Algorithmic type inference | `finfer` |
| Skeleton inference | Algorithmic skeleton inference | `sk_infer` |
| Consistency | Algorithmic consistency | `join_sk`, `join_var`, `assign` |
| Subtyping | Algorithmic subtyping | `sub`, `sub_flex` |
| Instantiation information | Constraint collection and solving for subtyping | `look`, `constr_collect_sub`, `constr_collect_eq`, `solve_eq`, `solve_sub`, `constr_solve` |
| Modal extension | `maetel/maetel.tex`, algorithm and elaboration | `sub_mod`, `join_mod`, modal cases in `finfer`, context locks |

Ghosts represent missing information; unresolved ghosts also permit
unknown leading quantifiers/modalities. They must be resolved or
rejected before typed syntax reaches the backend. Unknown type
variables are solved only with monotypes, with kind, scope, and occurs
checks. Polymorphic/modal instantiations obtained through `look`
retain supplied structure. Preserve live unknown entries on scope
exit and across top-level definitions.

Source-level binding and annotation requirements are specified in
[the inference section](modal-effects-spec.md#5-type-inference-and-polymorphism).
Keep unknown entries across unsigned top-level bindings and supply explicit
Fresco cases for Links type abstraction/application. The reference parser's
support for type application does not provide its missing inference case.

## Implementation in Links

The final frontend uses Fresco for all in-scope constructs. Keep the
Links syntax tree, typed intermediate representation, and runtimes.
Transitional implementations may coexist while individual changes
build; remove the old effect inference path before completion.

Add scoped rows and modal types to the shared representation and
update maps, folds, substitution, free-variable collection,
serialisation, and printing. Separate Fresco modes, skeletons,
contexts, and constraints from user types, and connect inference to
typed Links syntax. Preserve source positions in errors.

Use `Arrow of typ * typ` and `LinearArrow of typ * typ` for contextual
arrows, retaining Links' tuple domain convention. Use
`Modal of typ Modality.t * typ` for modal types. Keep scoped effect
rows as `typ EffectRow.t` in contexts and modalities; they are neither
value-type constructors nor row-kinded type arguments. The old
`Function`/`Lolli` constructors remain during migration. Their latent
effect rows must not be used to encode contextual arrows.

Add modal kind metadata to quantifier records, with `Any` as the
default for existing callers. Keep `Kind.t` and its existing
record/variant/linearity restrictions unchanged. Fresco contexts bind
modal kinds by variable identity, as in Aghilas' context. Freshening,
renaming, closure conversion, and binder copies preserve the metadata.
Legacy HM operations that cannot retain an `Abs` constraint reject it
before mutating type variables. Named type/effect declaration parameter
metadata must also retain modal kinds.
Contextual alias application and recursive unfolding must use structural
substitution and preserve quantified/modal bodies. The legacy alias
helpers also instantiate leading quantifiers and remain confined to
the legacy frontend during migration.

Use `TypeParameter`, containing `Kind.t` and `ModalKind.t`, with
an `Any` default and `Abs` permitted only for primary kind `Type`.
Use it in abstract type arities, alias parameter descriptors, and
`rec_appl.r_quantifiers`. `Quantifier.to_parameter` copies both kinds
without allocating a variable identity. Structural consumers retain
the full descriptor. Legacy consumers use a checked projection to
`Kind.t` which rejects `Abs`. The legacy precheck must also inspect
unused declaration parameters on abstract, alias, and recursive
applications. Contextual structural application validates argument modal
kinds using the contextual kind checker.

| Stage | Files and required changes |
|---|---|
| Parsing | `lexer.mll`, `parser.mly`, `sugartypes.ml`: declarations, modalities, handler annotations, freezing |
| Traversals | `sugarTraversals.ml`, `transformSugar.ml`, module/type-variable desugaring: visit effect arguments and binders |
| Types | `types.ml/.mli`, utilities and printers: separate effect rows, modal types, unchanged record/variant rows |
| Inference | `typeSugar.ml`, new Fresco modules, `unify.ml`, `generalise.ml`, `instantiate.ml`: replace effect/HM inference; adapt structural row solving |
| Elaboration | `desugarEffects.ml`, `desugarDatatypes.ml`, `sugartoir.ml`, `compilePatterns.ml`: preserve identities, ambient rows, explicit type applications |
| IR | `irCheck.ml`, `irTraversals.ml`, optimiser/closure passes: scoped effect checks and new type traversals |
| Execution | `value.ml`, `evalir.ml`, `irtojs.ml`, `lib/js/jslib.js`: nearest handler, outer clause context, deep resumption |
| Migration | `core/lib.ml`, `prelude.links`, `lib/stdlib/`, tests/examples: built-in groups, modal annotations, polymorphic signatures |

The OCaml runtime already searches for the nearest handler containing
an operation name (`value.ml:664--694`), removes that handler during
its clause, and reinstalls it for deep resumption. Retain this with
stable operation identities. Complete groups make runtime selection
agree with consuming one row occurrence. The JavaScript runtime has
corresponding deep-handler support. Erase modal evidence and freezing
after checking; retain explicit type operations required by Links IR.
Keep JavaScript's `Higher_Order_Continuation` representation; it implements
continuations independently of the excluded higher-order effect declarations.

### Frontend and migration boundaries

Follow the [arrow migration guidance](modal-effects-spec.md#82-migrating-effect-annotated-arrows)
when migrating examples. The source is thesis chapter 3,
`chapters/overview.tex`: the `map`/`iter` examples place an absolute modality
around the outer type while leaving callback arrows contextual; handler
arguments use relative modalities to retain other ambient effects. Aghilas'
`tests/pass/list-map-fold.mle` exercises the same pattern. Preserve callback
effects during migration and test both pure and effectful uses of `map`.

Keep the distinction between implicit arrows and legacy annotated arrows in
the parser. During transition, `DesugarLegacyTypes` converts implicit arrows
before legacy type-variable/effect desugaring and rejects modal constructs.
Run it after imported syntax is loaded. The contextual path preserves the
new nodes. Use the temporary normaliser in legacy built-in type-string readers.

Source-level tests need a contextual entry point with a small primitive
environment before the whole prelude is migrated. Lower checked declarations,
qualified operations and general freezing before `sugartoir.ml`, whose old
entry points reject those nodes. Once migration is complete, batch, REPL and
typed-frontend rechecks must all use Fresco. Include type-string readers used
by compiler transformations when removing temporary legacy routing.

Inventory in-scope syntax constructors, primitive signatures and old effect
annotations before migration. Migrate built-in type strings before removing
the old parser productions; they are parsed during initialisation. Use the
specification's compatibility table for source changes. Keep existing suite
feature settings, including typed-IR and rechecking settings.

`Process` takes a mailbox message type because its old effect-row parameter
contains an excluded effect tail. The specification gives the selected actor
signatures. Primitive operations can retain their specialised runtime calls.
Scope the mailbox unknown with the spawned body and connect receive-pattern
types to the resulting `Process(a)`. Handlers are not transferred to a spawned
process, so its body receives an absolute context of its own.

### Effect and operation resolution

Use separate effect lexical frames and module exports. Frames retain every
candidate for an operation short name. Opening the same declaration repeatedly
deduplicates identities; inner frames hide outer candidates. Effect short names
follow Links' module/type shadowing convention. Use the same resolved operation
identity in invocations, patterns and runtime dispatch.

Resolution has explicit input/output state for scopes, declaration headers,
loaded modules and identity allocation. Copy the mutable module-name allocator
before traversal. Failed resolution leaves the input state unchanged; successful
interactive imports reuse identities. Commit resolution and typing states
together only after checking succeeds.

Allocate effect identities before checking bodies, allowing self references.
Headers contain source names, positions, ownership and arities. Keep full
parameter binders and signature syntax on declarations. Infer ordinary parameter
subkinds during type-variable resolution; avoid guessed subkinds in early
headers. Fresh rigid formal IDs prevent capture of outer variables. Contextual
elaboration checks signature closure before allocating annotation unknowns.

### Shared type and traversal contracts

`EffectRow.match_equal` and `EffectRow.match_subeffect` return ordered argument
pairs before payload comparison. `Modality.right_residual` uses the prefix
construction above. Implementation status and completion checks are in PLAN.md.

`Quantifier` stores variable identity, `Kind.t`,
and `ModalKind.t`; constructors default to `Any` and reject `Abs` on
row/presence binders. Copies retain both kinds. Structural substitution
preserves `Abs`; legacy inference and type application reject it.
Binder identity equality remains separate from full binder comparison.
Printers retain existing `Any` output and show `::Abs`.

The legacy guard checks recursive arguments and raw declaration bodies,
using `rec_appl.r_body` without unfolding or instantiation. It checks each
body once per call and every occurrence's arguments. Alias construction
during desugaring may inspect incomplete bodies; inference requires complete
declarations before mutation.

Shared types contain contextual `Arrow` and
`LinearArrow` nodes, `Modal`, and scoped effect row/modality aliases.
Traversals and substitution visit effect arguments and modal payloads;
printers preserve row/mask order. Effect arguments are invariant in
variance checks. Modal payload variance follows the payload type;
ordinary linearity also follows the payload and ignores effect
arguments. Contextual arrows have no latent effect row. Legacy
inference rejects these constructors before mutation.

Non-recursive IR equality uses scoped row matching, mask multiset
equality, full modal payload comparison, and modal binder kinds.
Within these comparisons, session input/output types include their
continuations. The transitional IR checker rejects recursive equality
involving contextual arrows or modal types explicitly. The existing IR checker accepts recursive
equality without comparing bodies; new modal types must not inherit
that shortcut. Recursive traversal and substitution remain required.
Contextual recursive comparison must replace this temporary rejection
before accepting recursive modal programs through the IR checker.

### Contextual recursive type operations

Apply aliases and unfold recursive declarations with capture-avoiding structural
substitution. Legacy helpers that instantiate leading quantifiers cannot perform
these operations. Preserve formal binders, nominal identities, quantified/modal
bodies and exported free-variable requirements.

Recursive comparison must account for actual arguments. Comparing only a
declaration name can accept unequal types; repeatedly unfolding growing
arguments can diverge. For example, `Nest(a) = Leaf(a) | Next(Nest(List(a)))`
generates new argument types indefinitely under naive unfolding. Use a checked
comparison strategy and test termination on equal and unequal non-regular
applications before enabling recursive modal types in the affected consumers.

### Ordered contexts and recursive inspection

`Unionfind.peek` reads without changing `find`. `rec_appl.r_body`
returns the formal `Quantifier.t` list alongside the raw body;
`tygroup.type_map` already stores this pair. Existing legacy guards
continue to inspect the body. Encode recursive declaration identities
with a separator between the name and group number: concatenation alone
can confuse `T1` in group 2 with `T` in group 12.

Use ordered contexts and checked assignment in
`frescoContext.ml/.mli` and `frescoTypeOps.ml/.mli`. Identify variables
by `Types.tid`: separate Unionfind points can denote the same variable.
Context entries retain both ordinary and modal kinds. Store solutions
in returned contexts; assignment must not mutate Unionfind points or
call the legacy unifier. Resolve existing solutions, check occurs,
kinds, and scope, then move flexible dependencies before the variable
being assigned. Reject dependencies on younger rigid variables.
Include record fields, row tails, presence variables, and effect
arguments in these checks.

`Unionfind.find` performs path compression. Use `Unionfind.peek` for
these checks; avoid mutable unfolding and
normalisation helpers. Exported types use fresh points.

Scope exit retains surviving flexible declarations and solutions,
removes local bindings and locks, and checks returned types and
retained solutions for escaping rigid variables. Follow
`lib/type.ml:protect_context`, which preserves flexible entries;
`lib/context.ml:protect_context` drops them. Export resolved types
using fresh, memoised points before later compiler passes can mutate
them. Keep row and presence unknowns in the same ordered context,
with structural solutions checked according to their primary kinds.

Recursive skeletons contain `Ghost` and `UniversalGhost`, including
holes inside fields and effect arguments. Conversion to
shared types rejects remaining ghosts. Retain the thesis consistency
rules' two bound-variable sets: when opening two matching quantifiers,
put the shared fresh variable in both sets. A ghost cannot be filled
with a type containing a variable bound on its own side. The reference
omits these restrictions; the direct and source-level probes below
exercise the resulting invalid refinement. A value-type unknown's solution
must be a monotype; supplied polymorphic/modal structure is handled
by `look`. Structural row solutions may contain supplied polymorphic
field types, whose comparisons use Fresco.

Preserve the monotype restriction through later row and presence
solutions. When a value unknown's proposed solution reaches a flexible
row or presence unknown, mark that dependency as requiring a monotype.
Apply the same check when solving it and propagate the requirement to
further dependencies. Follow existing solutions and reject `ForAll`
or `Modal` anywhere reached. Store solutions and requirements together
in the returned context, preserving requirements through moves, merges,
and scope exit. Independent rows may still contain polymorphic fields.

Rigid row and presence variables count as monotype atoms, as rigid
type variables do in the reference. Apply the ordinary scope checks;
do not impose a new source-level row kind. Later instantiation of a
quantified row may supply polymorphic fields without changing an earlier
flexible context solution. Test both assignment orders, propagation
through tails and presences, older/younger rigid dependencies, and
quantified record identities instantiated with polymorphic fields.

### Modal-kind analysis and well-formedness

Modal kind analysis must account for declaration arguments. The
reference's `context.ml:get_kind` returns `Abs` when a constructor name
has already been visited, even if its arguments differ. Use a finite
fixed-point analysis of declaration identities and argument modal kinds
for recursive declarations. Start at `Abs` and propagate `Any` from
contextual functions and relevant parameters until the results stop
changing. Inspect declaration bodies so unused parameters do not affect
the result. Check kind validity separately from this classification.
Cover nested applications and recursive aliases with changing arguments.
Supply each raw declaration body with its `Quantifier.t` binders, so
formal variable identities map to the argument-kind vector. The current
`rec_appl.r_quantifiers` parameter descriptors do not contain those
identities; `r_body` alone is insufficient. Avoid legacy unfolding in
this analysis.

Implement classification and well-formedness separately in
`frescoKind.ml/.mli`, using callbacks for variable solutions, raw
declarations, abstract constructor rules, and effect declarations.
Classification takes variable, raw-declaration, and abstract-constructor
callbacks, so it has no dependency on the later context module.
Local quantifier and formal-parameter bindings take precedence over the
variable callback. Classification alone does not establish well-formedness.
Well-formedness visits every child, including absolute-modal payloads
and unused constructor arguments. Check argument bodies as well as
their supplied primary-kind tags.

Use an internal Boolean summary for row and presence payloads without
giving their binders modal kind `Abs`. Closed rows and absent fields
contribute no contextual payload; present fields use their payload
kinds. Unresolved row/presence variables without an absolute-payload
requirement prevent an enclosing record or variant from being classified
as absolute. Inspect known solutions and retained payload requirements.
Session input/output types combine payload and continuation kinds;
selection/choice types combine branch kinds. Ordinary linearity and
session restrictions remain separate checks.

Create fixed-point states on demand and revisit callers when results
or argument summaries change. An `Any` result remains `Any` if more
arguments become possibly contextual. Include captured parameter
summaries in recursive-binder states. Abstract constructors use explicit
rules keyed by identity: lists and map entries depend on their payloads,
access points on their protocols, and unknown abstract constructors
default to `Any`. Use an explicit rule for the mailbox payload of `Process(a)` after migration.

`frescoKind.ml/.mli` implements this classification. Its callbacks
provide variable declarations and solutions, raw recursive declarations,
and abstract-constructor rules. Declaration states contain the declaration
identity and Boolean argument summaries. Recursive-binder states also
contain captured bindings; solution states use variable identities.
Re-evaluate demanded states when summaries change or new states appear.
Every result starts at `Abs` and can change once to `Any`. Recursive
references to a bound variable reuse its existing state.

For well-formedness, validate actual primary-kind structure, ordinary
subkinds and modal kinds separately. Check each argument's tag against both its formal
parameter and its body. Check all application arguments even when the
result ignores them. Check session continuations and branches as sessions.
Existing `Types.Base`, `Unl`, `Session`, and `Mono` predicates use mutable
point reads or legacy unfolding; implement read-only checks with `peek`.
Do not copy the existing `Mono.type_satisfies` call that supplies `Session`
to its restriction predicate. An explicit ordinary `Mono` requirement is
separate from monotype obligations on value-unknown solutions.

For an explicit ordinary `Mono` parameter, a rigid variable declared
`Any` fails: substituting a polymorphic type for that variable would break
the parameter contract. A rigid variable declared `Mono` succeeds.
The syntactic monotype check still accepts an older rigid `Any` variable
as an atom. If the unknown being assigned itself has ordinary restriction
`Mono`, its solution must also pass the stricter ordinary-kind check.
Keep these checks separate and do not narrow rigid declarations.

Use explicit ordinary-kind entailment in this checker. `Base` entails
`Mono`; `Session` does not, because session payloads may contain
polymorphic or modal types. The legacy `Restriction.min` relation accepts
the latter inclusion and cannot serve as an entailment test. Empty
`ForAll` binder lists are transparent for `Base` and `Mono`; the
syntactic monotype traversal also treats `ForAll([], A)` as `A`.
Non-empty quantifier lists and modal types fail a `Mono` requirement.

At each recursive application, check its actual arguments. Validate each
raw declaration body under its own formal binders once per check, retaining
pending checks for mutually recursive bodies. Do not substitute arguments
or skip argument checks when a declaration is already active. Contextual
named type declarations return `Type`; reject legacy recursive effect
aliases. Preserve recursive type and row binders with their stated kinds.

Supply a separate effect-parameter callback to well-formedness checking;
keep resolution headers separate from typed signatures. Check effect
identities, arities and ordinary/modal parameter kinds, including identities
in masks. Check all operation arguments and results at `Abs`, with a
provisional self header in scope.

During contextual effect declaration elaboration, require closed operation
signatures with only explicit effect parameters and nested quantifiers.
Allocate fresh rigid formal IDs for each declaration; an enclosing type
variable with the same name must not be captured. Reject undeclared named
variables, including variables written as flexible.
Reject remaining anonymous type, row, and presence placeholders before
allocating unknowns. This follows the reference's explicit declaration
parameters and bound-variable lookup. Resolution preserves anonymous row
syntax for this elaboration check. Expression annotation holes are a separate
part of contextual term elaboration.

`FrescoKind.check`, `check_effect_row`, and
`check_effect_signature` validate shared types. Source elaboration must reject
signature placeholders before allocating unknowns. Structural
validation queues kind requirements after checking all children. Raw declaration
bodies are checked once under
their own formal binders; each application still checks its arguments.
Callback solutions are checked outside use-site binders. Callback solutions
must be acyclic; explicit recursive type and row binders remain supported.

Ordinary recursive summaries use a least fixed point for `Session` and
a greatest fixed point for the other requirements. Recursive values are
checked through their bodies: the legacy default `Unl` on a recursive
binder does not prove its body unrestricted. Named recursive applications
require available declaration linearity for an `Unl` check. Effect
descriptors and explicit signature parameters must have primary kind `Type`,
including descriptors used by relative masks. Nested quantified row and
presence variables remain valid in signatures.

### Checked assignment and kind requirements

Use persistent ordered contexts and a strict assignment operation.
Keep declared ordinary and modal kinds unchanged. Assignment validates
current guarantees, follows solved dependencies, checks occurs and scope,
and moves younger flexible dependencies before the variable being solved.
Rows and presences retain monotype requirements through these moves and
through later solutions. Reject assignments to rigid or already solved
variables; consistency later compares solved targets.

The later consistency layer can refine ordinary flexible requirements by
introducing a fresh variable with a stronger ordinary kind and assigning
the existing unknown to it. For example, introduce `rho'::Unl`, assign
`rho := rho'`, then assign `alpha::Unl := Record(rho)`. Dependency movement
places `rho'` and `rho` before `alpha` where needed. For an already solved
row, refine its flexible field and tail dependencies without replacing
its solution. Propagate monotype requirements to fresh representatives.
Failure of strict assignment before this refinement is not by itself a
source-program rejection. This keeps the well-formedness descriptor API unchanged.

Use an abstract `FrescoContext`, with `FrescoTypeOps.assign`
delegating to its checked assignment operation. Context entries retain
declaration order, and lookup uses variable IDs. Type unknowns initially
require monotypes; row and presence unknowns acquire that requirement when
needed. Checks and dependency collection precede the returned context update.
Term and lock insertion also validate their types against the current context.

Recursive inspection tracks bound variables, active recursive binders,
nominal declarations and point paths separately. A point cycle must pass
through a `Recursive` node. The repeated point may contain another
constructor; an unrelated outer recursive binder cannot justify a cycle.
Entering a raw nominal body resets the point path and uses the declaration
guard. These rules accept shared recursive graphs while rejecting unguarded
point cycles. Keeping recursive binders separate also prevents a quantifier
with the same ID from hiding an occurrence of the assignment target.

### Scope exit and detached export

Scope exit takes explicit live type roots with their lexical binders,
and the innermost marker. Expand solved variables in those roots first and
return rewritten roots with the resulting context. This permits a local
solution `beta := a` in `forall a. beta`, whose rewritten root is
`forall a. a`. Preserve the current prefix, including unknowns moved before
the marker. Retain suffix flexible entries reachable from rewritten roots,
prefix terms, solutions, and lock arguments. Remove local rigid, term and
lock entries, the marker, and dead suffix unknowns. Reject free occurrences
of removed rigid variables in rewritten roots or retained solutions. Root
binders cannot hide free variables in a separately retained solution or raw
declaration body.

Each root states its primary kind (`Type`, `Row`, or `Presence`). Check
the original root before substitution and the rewritten root in the reduced
context. Quantified binders closing a local rigid variable must preserve its
ordinary and modal kinds. A `Recursive` binder carries no declared `Abs`
constraint, so it can close only a matching `Any` rigid variable. Distinct
nested recursive binders must have their bodies checked even when they reuse
one variable ID; only a repeated occurrence in a recursive graph ends that
traversal.
Apply closing metadata checks to the original root syntax before copying.
Binders inside stored solutions and raw declarations have independent scope.

`FrescoContext.leave_scope` implements this operation, also exposed through
`FrescoTypeOps`. It returns fresh root points while retaining raw nominal
callbacks under the existing stable-callback contract. Recursive kind states
now distinguish syntax nodes and retain active recursive nodes separately
from lexical variable bindings.

Export several types together to fresh, memoised points. Return a declaration
table alongside the types for free rigid and unresolved flexible variables,
including ordinary kind, modal kind, freedom, and monotype requirements.
`Types.Var` alone cannot preserve `Abs` or structural monotype requirements.
Keep this table for later consumers; backend type operations must account
for it before using exported types. Read-only representative lookup is needed to retain
sharing between points in one Unionfind class without path compression.
Free variable occurrences with the same ID share one exported variable point.
Keep bound occurrences separate from free occurrences with the same ID.

Copy raw nominal declaration bodies and rebuild callbacks over the copied
graph. Snapshot declaration linearity. No exported callback may retain source
points or the inference context. Transitional export rejects `r_unwind`
explicitly; supply capture-avoiding contextual unfolding before
recursive exported types reach consumers that unfold them. Preserve actual
cyclic point graphs with an explicit `Recursive` binder, while rejecting
cycles without such a binder.

`FrescoContext.export`, also exposed through `FrescoTypeOps`, implements
detached batch export. Its variable table follows context order. Context
entries determine free-variable freedom, and rigid entries retain their
declared kinds with no flexible monotype flag. Equal annotation binder lists
share an output scope; syntax binders retain distinct identities. Copying
uses separate solution-lookup and output scopes, so a solution can close under
an output binder without changing how its free variables are resolved.

Raw declarations use their own binders and the supplied declaration callback.
Export snapshots bodies and optional linearity, then rebuilds callbacks over
copied data. Exported unfolding raises
`FrescoContext.Unsupported_recursive_unfolding` until contextual unfolding
is supplied. For point cycles,
copy non-recursive nodes separately when their lexical scope changes, and
close an active recursive node using its captured scope. Scope exit uses the
same cycle rule and checks closing metadata before copying any roots.
Identify active recursive nodes by their syntax identity, including nodes
nested inside another point descriptor or supplied directly as roots. Reuse
the destination point for an immediate recursive descriptor; otherwise keep
a fresh point for back references while preserving the first constructor.
Completed-point memo keys include the active recursive context as well as
lexical scope. A result computed while a recursive node is active cannot be
reused where that node's body must be checked or copied again.

### Skeletons and substitution

Use a separate recursive `FrescoSkeleton` datatype. Mirror the supported
shared constructors with skeleton children, including row fields, presences,
effect arguments, modal payloads and session types. Add value-type `Ghost`
and `UniversalGhost` constructors. Keep row and presence uncertainty in their
existing variable categories. Store raw nominal bodies as skeleton data so
that no shared-type wrapper can hide a ghost.

Convert batches of roots with explicit binders and primary kinds using the
current context's checking environment. Preserve variable nodes and IDs;
leave solutions, free-variable kinds and monotype requirements in the
persistent context. Representation conversion does not expand solutions.
Conversion back to shared types rejects both ghost constructors anywhere
reachable, including raw nominal bodies, then checks the resulting roots
using their rebuilt declaration callbacks. Detached export follows this
conversion through `FrescoContext.export`.

`FrescoSkeleton.of_types` and `to_types` implement this conversion. Root
binders shadow context declarations normally because conversion retains the
context. Row tails are skeleton nodes. Nominal declarations store formal
binders, a skeleton body and optional linearity as data; body mutation is used
only to construct fresh mutually recursive graphs during conversion. Distinct
declaration records must have distinct identities. Output callbacks refer to
the converted graph, and checking uses these bodies even when the supplied
environment contains an older declaration callback.

Before consistency, add skeleton free-variable collection, capture-avoiding
substitution and quantifier freshening. Solution expansion and scope exit must
also preserve ghosts. A variable-occurrence projection may reuse the checked
context operation, but must retain lexical binders, check vacuous binders,
and treat raw declaration scope independently. A free-ID set alone loses
these distinctions. Guessing follows these operations: the reference fills
ordinary ghosts and removes universal ghosts while preserving supplied
quantifiers and modalities; assignment then checks the monotype requirement.
`look` also collects and solves constraints.

Distinguish free-variable collection from root-scope substitution.
Free-variable collection includes raw declaration captures under each
declaration's own formals. Root substitution and quantifier opening traverse
application arguments but retain referenced declaration records unchanged.
For `D() = a`, opening `forall a. D()` freshens the root binder and leaves
the raw free `a` unchanged. Opening binders to fresh IDs also separates these
captures from the bound-variable sets used by consistency.

Keep declaration identities and records shared across these root operations;
reject distinct records with the same identity in a batch. Global substitution
through raw declaration captures is deferred. It would need one coordinated
declaration snapshot across roots, context solutions and callbacks, preserving
nominal identities while preventing old and changed bodies from being mixed.

`FrescoSkeletonOps` implements free-variable collection, simultaneous
capture-avoiding root substitution and quantifier opening. It checks primary
categories, nearest-binder categories, declaration identities and graph
cycles. Ordinary/modal checks remain with the context. Opening preserves
quantifier metadata and gives renamed occurrences fresh rigid IDs.

Binder-renaming caches use finite source lexical identities and active
recursive syntax identities; copied-point caches also retain output mappings.
Inserted replacements are copied in a separate substitution mode. This
prevents repeated substitution and preserves captured scope on cyclic graphs.
Completed recursive constructors are reused in equal scopes so repeated bare
roots preserve sharing and the identity of their back-reference descriptors.

### Modal-kind refinement

Follow `maetel/maetel.tex`, algorithmic kind checking rules `FlexAbs` and
`FlexDef`. A requirement operation returns an updated context. An unresolved
flexible Type variable can acquire an `Abs` requirement; a solved variable
checks its existing solution and strengthens relevant flexible dependencies.
Preserve declared metadata by using a fresh stronger representative or a
separate effective requirement. Never narrow a rigid variable. Preserve
ordinary kinds, monotype requirements, ordering and scope restrictions.
Failure returns no context changes.

For Links records and variants, use an internal absolute-payload requirement
for flexible Row and Presence variables. Their declared modal kind stays `Any`.
Propagate the requirement through present fields, flexible tails and presences,
and follow solved structural variables. Rigid row/presence variables provide
no absolute-payload guarantee. Preserve requirements through assignment,
refinement, scope exit and export, and expose them to kind classification.
This is a Links extension to the thesis' value-type rules.

Require `Abs` only along paths contributing to the containing type's modal
kind. An absolute modal type is already absolute; its payload must be
well-formed but need not itself be absolute. Relative modalities inherit their
payload's kind. Unused declaration parameters do not affect classification.
The quantified-type classification rule above uses temporary `Abs` bindings;
requirement refinement must still preserve declared rigid kinds.

Use requirement refinement at the thesis' instantiation, guessed-monotype
checking and modality transformation checks. For variable access, try the
right residual before the absolute fallback, following the thesis' algorithmic
variable lookup. Keep each failed attempt's context separate from the next.

### Parameterised-effect matching order

The user selected effect-argument equality before payload `Abs` refinement on
6 November 2026. This resolves the alternatives identified in
`maetel/maetel.tex`, subsection "Parameterised effects".

Try the scoped-effect matching route and its argument equalities first. On
failure, discard all context changes from that attempt and try absolute-payload
refinement from the input context. On success, retain those equalities. A later
failure does not backtrack to a different earlier choice. An already-established
absolute payload remains usable through the ordinary absolute rule without
adding unnecessary constraints. Test the selected order, rollback on failed
matching and the additional rejections caused by committing early equalities.
Do not claim completeness for the parameterised extension.

## Value linearity and legacy effect sugar

Ordinary value linearity remains separate from modal kinds. Preserve usage
checks across branches, unlimited closure capture checks, and the distinction
between contextual `Arrow` and `LinearArrow`. A `Modal` node inherits ordinary
linearity from its payload; `Abs` does not imply `Unl`. Fresco's skeleton and
full checks of one argument must count its source evaluation once. Preserve
ordinary requirements through later type, row and presence assignments.
Relevant existing checks are in `typeSugar.ml` (usage, function capture and
recursive bindings), `Types.Unl`, and `FrescoKind`.

With control-flow linearity disabled, `LinCont.make_continuation_type` creates
unlimited resumptions and continuation-linearity updates are disabled.
Deep-handler clause capture checks do not protect every linear value held by
the handled computation's continuation. A reusable or discarded resumption can
duplicate or drop such a value even for an operation `() => Bool`. The Links
example in `~/code/algebraic-effects/linear-handlers/sections/introduction.tex`
records this problem. The user selected preservation of the current ordinary
checks and CFL-disabled behaviour on 6 November 2026. Defer repairs to the
continuation interaction. Restricting operation payloads to `Unl` alone would
not address continuation captures.

Preserve ordinary linearity in actor signatures: `core/lib.ml` gives `spawn` a linear body function and
allows `Send` to transfer a linear message. Source spawn checks that its discarded
result is unlimited. The specification makes the message parameter's ordinary kind explicit along
with `Abs` and uses a linear spawned-body function. Do not infer `Unl` from `Abs`.

`desugarEffects.ml` performs more than abbreviation expansion: it shares
anonymous effect tails, inserts omitted alias effect parameters and adds missing
operation fields with polymorphic presences. These operations depend on the old
effect representation. Contextual arrows use the ambient row without creating
such hidden effect parameters. Do not reproduce the old sharing policy for
scoped effects. Preserve ordinary record/variant row arguments; the current
parser shares their braced argument production with legacy effect rows.

The old `~>`/`~@` and `{:T}` syntax supplies `wild` and mailbox `hear` entries.
The specification replaces these with named built-in effects. Preserve the
existing root behaviour from `core/lib.ml`'s `closed_wild_row`: the user selected
initial ambient context `Wild` on 6 November 2026. Reserve `Wild` and
`Receive(a)` for built-in behaviour and reject user-written handlers selecting
them. Specialised primitives keep their current dispatch.

The user also selected implicit `modal []` for global function signatures
without an absolute modality, following the thesis' "Global functions are
absolute" subsection. Insert the default during signature elaboration and
preserve explicit absolute modalities and quantifier scope. It supplies no
implicit generalisation and does not change ordinary type-kind defaults.
Test omitted versus explicit empty modalities, explicit non-empty modalities,
quantified signatures, recursive signatures and an effectful callback to `map`.
The empty-context default for a function is independent of the program's root
context `Wild`.

Audit the legacy printing options separately from parser/desugaring policies.
`open_default`, `final_arrow_shares_with_alias` and `all_implicit_arrows_share`
affect elaboration. Presence omission, operation contraction and alias/arrow
printing options format legacy types. Reclassify `effect_sugar.tests` as migration
rejection, unaffected structural-row and modal round-trip cases. A migrated
`map` with an effectful callback should exercise the replacement of old effect
sharing by contextual arrows and modal typing.

## Reference checks and regression coverage

Language examples and their required outcomes belong in the
[specification](modal-effects-spec.md#8-compatibility-and-examples). The checks
below record reference defects and cases to adapt when testing the compiler.

### Reference verification and corrections

Built a copy of the reference in `/tmp` on 6 November 2026. Its suites
pass: 57 Fresco and 25 modal/data-type tests. Additional probes found:

1. Identical `[state int,state bool]{unit}` parameter annotations fail
   consistency. `join_sk_mod` and `solve_eq_mod` fold right-to-left
   while matching first occurrences. Use a shared left-to-right
   equality matcher in consistency and equality constraint
   collection/solving. Add reflexivity tests for both paths with repeated
   occurrences and distinct argument types.
2. A group with operations a and b accepts a handler supplying only a
   while its body invokes b; evaluation fails. Enforce complete groups.
3. Annotated handlers parse but lack an inference case. Implement the
   annotated case using the handler rule and checked type arguments.
4. Unsigned global definitions can lose unknown type variable entries
   when the driver discards its updated context. Preserve those entries
   without introducing let generalisation.
5. Local unannotated identity at two types fails; signed recursion
   runs and unsigned recursion fails. Preserve these defaults.
6. Return-only handlers crash in the reference through `List.hd`.
   Retain Links' identity-handler rule explicitly.
7. The residual for a lock removing two State occurrences and a guard
   removing one restores the first occurrence, although the guard's
   output contains the second. Use the prefix construction above and test literal output equality
   and normalised masks of the composed modalities.
8. `join_sk` accepts `forall a. a -> Ghost` against
   `forall a. a -> a`, in both orders, violating the thesis' restriction
   on filling ghosts with bound variables. Skeleton inference for
   `f 1`, with `f : forall b. Int -> (forall a. a -> b)`, produces
   the first skeleton. Passing a frozen `f 1` to a function expecting
   `forall a. a -> a` reaches this invalid join; the subsequent full
   type check rejects the program. Require the direct joins to reject.
   Keep the whole-program rejection test, and acceptance tests where
   the expected result is `Int` or the argument is an identity lambda.
9. `context.ml:get_kind` classifies `box (box (int -> int))` as `Abs`
   for `type box a = Box of a`. It also classifies `nest int` as `Abs`
   for `type nest a = Leaf of a | Next of nest (a -> a)`. Both are
   accepted as ordinary operation arguments by the reference; both
   contain contextual function values and require kind `Any`. The
   name-only recursion check skips the inner constructor's payload.
   Regular `nest int` and recursion through an absolute function
   modality are positive controls; regular `nest (int -> int)` is a
   negative control. Links permits changing arguments in recursive
   aliases, so kind classification must handle this case. Add classification and
   operation-declaration rejection tests.

Keep tests for these corrections alongside the adapted reference tests.

### Fresco regression coverage

Rechecked all 57 files in `tests/fresco/`: 43 acceptance files succeed
and 14 rejection files report typing errors. The combined
`tests/pass/fresco.mle` also succeeds. Use the following pairs when
adapting the reference tests to Links:

| Files under `tests/fresco/` | Behaviour to preserve |
|---|---|
| `pass/a7`, `fail/a8` | Quantifier position changes whether `choose id auto` checks |
| `fail/c1a`, `pass/c1b`, `pass/c1c` | Parameter annotations and expected function types supply polymorphism |
| `fail/e1a`, `pass/e1b` | Eta expansion permits the required quantifier position |
| `pass/` and `fail/` versions of `e3b`, `e7`, `f2`, `f4` | Freezing supplies polymorphic argument information |
| `pass/f11a`, `pass/f11b`, `fail/f11b` | Local lets preserve inferred types without generalisation |
| `pass/f7`, `fail/f7` | Freezing retains the outer Church-list quantifier |

Split the native and Church examples in rejection files `b7`, `e1a`,
`e5a`, `e5b`, `f3`, and `f11b` into separate Links tests: the reference
driver stops at the first error. Each isolated Church example was
also checked and rejects. Assert inferred type structure for `a1`,
`a2`, `b1`, `f6`, and `f8`--`f10`, where successful exit alone does
not distinguish unknown monotypes from retained quantifiers.

Add direct context tests for unknown-variable ordering, moving
dependent unknowns before assignment, rigid-variable escape, occurs
checking, modal kinds, ghost refinement, and retention of live unknown
entries on scope exit. Add Links tests for n-ary and zero-argument
functions, polymorphic record/variant fields, row and presence
variables, explicit type abstraction/application, and signed recursion.
Reference pairs are nominal datatypes and functions are curried.
Provide implementations for reference `val` helpers in runnable tests.

### Handler migration and modal examples

Convert handler tests "Operation parameter pattern-matching" (7)--(9) and
the six affected handlers in `examples/handlers/nim.links` to one clause per
operation containing a `switch`. Preserve pattern order and resumption calls.
Add rejection coverage for repeated operation clauses.

Retain a nested Tick example in which the inner handler produces `1` and an
invocation under the outer handler produces `10`, giving a total of `11`.
Adapt modal-access rejection from reference `tests/fail/leak-effect-paper.mle`
and combined modal/polymorphic acceptance from `tests/pass/fresco.mle`.
