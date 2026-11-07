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

Parse `List A` as the existing list datatype node. Require parentheses around
nested list element types, as requested by the user on 6 November 2026.
The list-element grammar must exclude an unparenthesised `List` type:
accept `List (List Int)` and reject `List List Int`. Add both parser tests
and retain the grouped printer output. Keep the internal element kind, list
constructor and runtime representation. A separate `List` token selects the
built-in type syntax; other constructor positions still accept `List`,
including variant labels, patterns and module/effect names. Rename the custom
`List` aliases in mutual-recursion fixtures to `RecursiveList`. Update both type printers
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
rules. The lexer shares its effect-angle mode between modalities and handler
annotations. A case's outer `->` leaves operation-pattern mode before scanning
the clause body. Test qualified effects, parameterised effects, nested handlers
and XML inside the computation and clauses. Check the generated grammar for
conflicts.

### Combined kind syntax and inference reuse

Present a value-type binder as `Type(linearity, restriction, modal_kind)`, for
example `a::Type(Any,Any,Abs)`. Parse this as the existing ordinary kind plus
modal metadata. Retain ordinary two-field annotations and the `::Abs` shorthand
with their existing defaults. Replace the stacked spelling in target signatures
and update both type printers and binder round-trip tests.

Current storage in `commonTypes.ml` separates the components:

```ocaml
Kind.t = PrimaryKind.t * (Linearity.t * Restriction.t)
TypeParameter.t = { kind : Kind.t; modal_kind : ModalKind.t }
Quantifier.t = { var : int; kind : Kind.t; modal_kind : ModalKind.t }
```

Fresco declarations likewise store `kind` and `modal_kind`. The combined surface
syntax does not require replacing these records. Keep ordinary and modal checks
independent. In particular, `::Abs` leaves ordinary inference/defaulting intact;
`Type(Any,Any,Abs)` explicitly permits linear values.

Reuse the occurrence-based constraint collection, consistency checks and
annotation/default handling in `desugarTypeVariables.ml`. Unannotated source
binders still default to modal `Any`; solver refinement applies to flexible
unknowns without narrowing declared rigid binders. Its `#add` operation
accumulates kind information and `#unbind` applies defaults. Extend this pattern
to collect modal requirements where needed. Solver refinement uses returned
Fresco contexts instead of mutating the elaboration pass's shared points.
Preserve the distinction between rigid source binders and flexible unknowns,
and between modal classification and checking a requirement.

Do not copy legacy ordinary-kind merges without checking their meaning:
`Restriction.min` treats `Session` and `Mono` differently from Fresco's explicit
entailment requirements. Retain both constraints when refining dependencies.
The modal requirement order is `Abs` admissible at `Any`, with propagation
through contributing type/row/presence dependencies as specified below.

### Reference choices

Use Aghilas' named declarations to group operations while using the thesis'
scoped rows for effects. Omit the reference's higher-order effect extension.
D3e removes its declaration flag and special row ordering. The lexer treats
`higher` as an ordinary identifier; `effect higher` fails to parse.
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

`FrescoKind.classify` uses temporary absolute summaries for quantified
value-type binders. Well-formedness still checks uses of binders against their
declared ordinary and modal kinds. Preserve ordinary kinds and leave declared
modal kinds unchanged for term checking, instantiation and exported binder
metadata. Row/presence binders receive no new absolute-payload guarantee.
Positive and negative tests separate quantified-type classification from
actual instantiation requirements.

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

### Subtyping and instantiation information

Follow the thesis' constraint order: collect equalities from left to right,
then the final subtyping constraint. In function mode, collect domain equality
before continuing with the result mode. Equality solving extracts information;
it preserves left rigid and flexible variables without assigning them. The
subtyping judgement subsequently checks the resulting instantiation. Full
support fills remaining ghosts and enforces the quantified variable's
requirements. Supplied quantifiers and modalities remain in explicit
instantiation arguments. They cannot become solutions of Type unknowns.

`FrescoConstraints` implements collection, extraction and `look`.
`FrescoSubtype` returns the output skeleton, persistent context and explicit
instantiation arguments. Each argument records the quantified parameter,
enclosing target binders and its position in the comparison. Scope exit
rewrites these arguments alongside the output skeleton, so target binders
can close an argument without escaping into unknown solutions. Row and
Presence parameters use their own primary categories, including unused
parameters and residual row fields. Skeleton checking permits only `Ghost`
as the expected type, as in the thesis' mode well-formedness rules.

D7c1b1 preserves the checked payload when rebuilding a modal subtype result.
Checking a quantified payload opens fresh target binders; its explicit type
arguments refer to those binders. Returning the original target would leave
those arguments without their binding type abstractions at source export.
Rebuild the original target's modal wrappers around the checked payload, and
record argument positions through that number of wrappers. A modality only
on the source adds no position in the target. All payload, scope and modal
transformation checks still run.

On 7 November 2026, the user chose modal kind `Abs` for ordinary ghosts during
skeleton inference. They also check at `Any` by the existing kind inclusion.
Universal ghosts retain their body's modal kind. Check supplied skeleton
structure and refine existing unknown type variables directly, using this
ghost rule. Ghosts need no stored kind metadata. Ordinary kind requirements
remain separate.

This permits an unused `Abs`-kinded quantified variable to be instantiated with
a ghost during skeleton inference. The thesis gives ordinary ghosts kind `Any`
and checks instantiation kinds in both inference passes. Aghilas' implementation
skips the instantiation kind check during skeleton inference. The selected rule
retains checks on supplied structure while accepting missing information at
`Abs`.

Skeleton refinement may change modal kind `Abs` to `Any`, for example when a
ghost is filled with a contextual arrow. Do not assume preservation of modal
kinds under skeleton refinement. Full inference must check every resulting
instantiation against the original quantified parameter's requirements and
repeat every modal-access check using the resulting types. An `Abs` judgement
from the skeleton pass cannot discharge these full-inference checks.

`FrescoSkeletonKind` checks skeletons through a read-only view shared with
`FrescoKind`. Ordinary ghosts contribute `Abs` to modal classification and
provisionally satisfy ordinary requirements. Universal ghosts use their body's
requirements. The checker validates every supplied child, preserves raw
declaration scopes and refines existing flexible variables through the returned
context. It allocates no replacements for ghosts. Shared-type checking retains
its existing rules. The pure unrestrictedness query supports private recursive
declaration groups during elaboration.

Tests cover an unused `Abs` parameter and an `Any` parameter whose ghost becomes
a contextual arrow. Full inference rejects a contextual-arrow instantiation at
`Abs` and repeats modal-access checks, including repeated effect arguments.

Modal checking first compares the source modality run and source payload with
the target run. It then checks the payload under the target lock and transformed
ambient row. Function mode applies the same transformation to the identity
modality. Skeleton mode omits this transformation. The existing equality-first
policy applies: an already absolute payload bypasses effect matching, a failed
match may try absolute refinement from the original context, and a successful
match remains committed if a later body check fails.

The reference implementation differs in several places. Its equality collection
prepends constraints during left-to-right traversal, and its modality solver
folds right while consuming first matching effect occurrences. Preserve source
order for both. Its modal check examines the payload before transformation,
classifies the result rather than the source payload, and omits the target lock.
Its modal function case omits the absolute-payload route. Follow the thesis'
SI-ModCheck and SI-ModFun rules with the project's parameterised-effect policy.
The reference's `get_guarded` already composes maximal modality runs.
Its LE-FlexR case copies the right variable's modal kind; use a fresh Any variable
as in the thesis. Apply effective kind requirements when guessing and splitting
unknowns, as specified by the persistent context operations.

### Reusing Links' monotype unification

Fresco solves unknown monotypes by first-order unification, as described in
`chapters/maetel/algorithm.tex`. Reuse and adapt the existing structural
unification in `core/unify.ml`: primitive and constructor matching, type
arguments, records/variants, row-label alignment, open tails and presences.
Extend the arrow cases for `Arrow` and `LinearArrow`. Keep scoped effect-row
matching and supplied polymorphic/modal structure with the Fresco rules.

The current public `Unify.datatypes` and `Unify.rows` operate on mutable
Unionfind points and return no context. Their legacy checks reject new arrows
and modal metadata, and failure can follow earlier mutations. Adapt lookup,
fresh-variable allocation, requirement propagation and binding to the ordered
Fresco context. Route solutions through checked assignment and return the
updated context. Failed alternatives must retain the input context. Reuse the
structural rules without bypassing modal kinds, rigid scope, dependency ordering
or monotype requirements.

Preserve authored recursive types through the recursive-type operations.
Legacy unification can infer recursive cycles according to a setting; Fresco's
unknown assignment still performs its occurs check. Shared row/presence logic
must retain constraints on later field solutions. Field comparisons involving
supplied quantifiers or modalities use the corresponding Fresco judgement.
Include accepted/rejected cases for all reused structures and failure rollback.

### Consistency, guessing and monotype unification

`FrescoConsistency` returns a persistent context and joined skeleton. Guessing
fills ordinary ghosts with fresh flexible variables, removes universal ghosts,
and retains supplied quantified and modal structure. Assignment then checks
syntactic monotypes, occurs, ordering and scope. Input skeletons are checked
before transparent aliases or other wrappers can be removed; unused actual
arguments retain their declared requirements. Session constructors also impose
their ordinary requirements during this check.

When one side is a session dual, remove a universal ghost on the other side
before normalising the dual. Otherwise a rigid session variable can cause
`UniversalGhost(~s)` and `~s` to fail consistency. Retain both bound-variable
sets in this step and use the existing recursive comparison. This does not
identify `s` with `~s` or change the unresolved row/presence duality limits.

Consistency implements the thesis' two bound-variable sets. Matching quantifiers
introduce a shared fresh binder on both sides; a one-sided quantifier extends
only its own set. Filling a ghost checks free variables after solution expansion.
Raw captures retain their independent scope. Requirement checks inside recursive
syntax must use the binder's captured environment, including references through
an inner recursive type beneath a shadowing quantifier.

Record/variant rows align common fields and solve open tails using checked
assignment. Missing fields in closed rows constrain unknown presences to `Absent`.
Two flexible tails receive the opposite missing fields and a shared fresh tail.
A repeated tail in the same orientation compares extra fields as absent. Row
and presence solutions may contain supplied polymorphic fields; dependencies
reached from a value unknown retain the syntactic monotype requirement.

Modality comparison matches scoped effect arguments from left to right and
preserves repeated-effect order and mask multiplicity. Failed checks expose no
context updates. Authored recursive types use contextual comparison. A proved
mismatch stops immediately, including when a different branch grows indefinitely.
Flexible obligations are solved in a returned context before comparison repeats.
Regular recursive skeletons with holes can produce a joined recursive graph;
reuse requires the full pair of types, primary category, both bound-variable
sets and structural progress. Unresolved growing comparisons use the distinct
error recorded in [recursive comparison](#contextual-recursive-type-operations).
For example, joining `A(Ghost)` with `B(Int)` for
`A(a) = a -> A(List(a))` and `B(b) = b -> B(List(b))` remains unresolved;
with unchanged recursive arguments, the join can construct a recursive skeleton.

Guessing freshens root quantifier and recursive binder IDs while preserving
metadata and raw declaration records. Fresh IDs avoid the input graph and
context. Recursive demand checks close replacements over their defining scope;
closed replacements are cached and unused substitutions are skipped.

Dualising an unresolved presence reports `Unsupported_presence_duality`; the
legacy helper asserts in this case. Resolved presences dualise their session
continuations. Common fields are compared first. If their comparison solves a
row tail, flatten both rows again and compare any exposed fields. This preserves
accepted Links cases where a common field closes the shared tail or extends it
with `End`.

A shared row tail that remains unresolved under opposite orientations
reports `Unsupported_row_duality`. Legacy comparison times out for empty and
disjoint flexible rows in the checked examples. It accepts rigid tails with
matching labels and can also accept flexible tails linked by an earlier
equation because its shortcut compares the original orientation flags.
Both assign a receiving type to an unchanged sending channel through an identity
function. A linked execution probe then waits indefinitely;
the correctly typed control returns `43`. The user approved rejecting and
documenting this legacy bug for both forms. Keep the unsupported-duality error
after expanding solutions, including links introduced by earlier fields.

The rigid-tail probe uses this identity function:

```links
sig convert : ([+||r::Session|+], [+||r|+]) ->
  ([+||r|+], ~([&||r|&]))
fun convert(a, b) { (a, b) }
```

Instantiating `r` with `X:!(Int).End` makes the second result receive on `X`.
The flexible-tail probe changes the result to
`(~([&||%s::Session|&]), [+||%s|+])` and uses `%r` in both inputs.

A one-sided `X:End` field is rejected under the default
`infer_recursive_types=guarded` setting; `all` and `positive`
accept it by inferring a recursive row. Fresco assignment retains its occurs
check. The user approved documenting and deferring support for these alternate
settings in D4j. Preserve this source migration gap until recursive row inference
has a separate design and tests. Choosing a closed row would discard other
solutions.

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

### D7 primitive migration

Use explicit contextual source signatures for primitives, with the existing
`Lib.nenv` identifiers and runtime implementations. Elaborate these signatures
in the initial Fresco environment so that `Wild` has the same declaration
identity as the ambient context. Keep primitive runtime types in the IR
environment after modal erasure.

Preserve the effect requirements of each legacy signature separately from
`Lib.PURE` and `Lib.IMPURE`, which control optimisation. For example, division
and numeric string conversion have no `wild` field in their signatures;
`take`, `drop`, `strlen`, `explode` and `implode` require `wild` despite their
`PURE` flags. Their migrated signatures therefore use `modal []` and
`modal [Wild]`, respectively. Changing those requirements or optimiser flags
would be a separate language or runtime change.

D7a covers first-order primitives. Actor, session and callback signatures have
separate migration checks in the following milestones. Database, lens and
session-failure primitives remain outside the current scope.

Nested regex execution exposed an IR coercion ordering issue: recursive
equality could report an inconclusive comparison before the checker attempted
contextual subtyping. Contextual coercions now try the subtyping proof first;
equality remains the fallback. The legacy ordering is unchanged.

**For user review: public XML variant aliases.** Publish `XmlVariant` and
`XmlItemVariant` for the recursive shapes used by XML conversion primitives,
alongside the existing `Repeat` and `Regex` names. This keeps printed primitive
types usable in source annotations. Equivalent user-written recursive aliases
remain accepted. The alternative is to print expanded recursive types at every
use. Nested forest/item round trips, nested regex sequences and printed-type
readback have source execution checks.

### D7 sections, patterns and record updates

Projection sections retain a quantified field type and row, with unlimited
requirements on both, following Links. Minus sections use the existing binary
primitive; frozen sections use the ordinary freezing check.

Keep both the scrutinee type and the type available after a pattern matches
among the typed pattern's scope-exit roots. Negative patterns remove their
labels from the latter type. `as` binders and pattern annotations use that
refined type; container patterns propagate their components' refinements.
List pattern refinements must agree across the head and tail.

Typed execution exposed existing pattern-lowering failures when an `as` binder
used a refined variant or container type. Bind a negative pattern's default
variable, and rebuild a matched record or list from its checked components
after the child patterns succeed. These operations reuse evaluated variables.

Record updates evaluate the base once, then every replacement in source order.
An updated field must exist and its old value must be unlimited. Untouched
linear fields remain available. Preserve Links' duplicate-label behaviour:
evaluate every replacement, retain the first, and require discarded results
to be unlimited. A guarded record update must check replacement access without
allowing an immediately evaluated expression to invoke effects absent from
the caller's ambient context.

### D7 regex syntax

Lower regex syntax to positioned constructors of the checked `Regex` and
`Repeat` types. Splices and replacement expressions have type `String` and
are evaluated once. Use the existing `tilde`, `ltilde` and `stilde` primitives.
Ordinary matching has no effect requirement. Capture-list matching and
replacement require `Wild`, following their primitive signatures. The legacy
operator typing rule omitted that requirement before desugaring to those
primitives; Fresco applies the same signature to direct and syntax-based calls.

Preserve the observed legacy splice order: sequence splices run right to left,
alternative branches run left to right, and pattern splices run before the
replacement expression. For example,
`"ab" =~ /{print("a"); "a"}{print("b"); "b"}/` prints `ba` before its result.
The `g` flag retains the existing single-replacement behaviour. These are
existing regex behaviours, separate from the effect migration.

The `n` flag has no runtime primitive implementation. Legacy typing aborts
with an assertion; Fresco reports a positioned source error. No native regex
runtime is added.

### D7 actor integration

**Transitional choice for review:** give the contextual mailbox constructor the
shared name `Types.mailbox_process`, public spelling `Process` and distinct
identity `MailboxProcess`. Its parameter is `Type(Any,Any,Abs)`. Keep the legacy
row-parameter constructor and its type-string environment until D7e removes
legacy inference. Using one identity with two arities would disagree with the
compiler's identity and structural comparisons. D7e must consolidate these
constructors after migrating their consumers.

Process identifiers remain unlimited when their absolute message type is
linear. Contextual primitive signatures supply the IR types for their existing
runtime identifiers. Generated spawn and receive calls use canonical primitive
references so user bindings cannot replace their implementation.

Ordinary spawn introduces a fresh absolute mailbox type under a scope marker.
Check its linear body in the absolute context `Wild, Receive(a)`, including an
absolute lock for captured values, and require its discarded result to be
unlimited. Export the mailbox type together with the body and its effect row.
Nested spawns use separate mailbox variables. Restore the caller's context on
scope exit, and retain ordinary usage checks for captured linear values.
When checking against `Process(A)`, use the supplied mailbox type `A` before
checking the child body. This retains polymorphic/modal payloads without
assigning them to a fresh monotype variable. Generated primitive signatures
are elaborated in the initial built-in environment, preserving their types
when user aliases shadow `Process` or `Location`.
The spawn skeleton exposes `Process` with a ghost mailbox payload when none
is supplied. The full pass checks the child body after the surrounding call
has supplied its expected mailbox type. This avoids placing an early monotype
variable in the skeleton where a later modal or polymorphic payload is needed.
Canonical `receive` instantiates `recv` with the ambient mailbox type before
checking patterns. Ordinary calls to the public polymorphic `recv` and `self`
retain Fresco's term-instantiation rules; modal or polymorphic mailbox types
use explicit type arguments, for example `~recv[Message]()`. This does not
change inference for other polymorphic functions.

D7c1b extends this rule to explicit locations, angels and client processes.
Check an explicit location in the caller's context before entering the child
scope, and evaluate it once. Generated calls use the canonical `spawnAt` or
`spawnAngelAt`, with canonical `here` or `there` for implicit locations.
The existing interpreter and JavaScript process implementations remain in use.

**Choice for review:** use a linear body for `spawnWait` and allow its result
to have ordinary kind `Any`. Legacy source checks accepted linear captures
and results, but the generated unlimited thunk could fail typed rechecking.
A linear thunk matches the runtime, which invokes the child once. Retaining
the unlimited generated thunk would reject those source programs.

**Choice for review:** require the `spawnWait` result to have modal kind
`Abs`. The child has its own mailbox and handlers, so a contextual function
returned from it could depend on effects unavailable in the caller. An
absolute modal function records its required effects and may be returned,
including a linear function. Permitting arbitrary contextual results would
need a separate rule connecting the child's effects to the caller's effects.
A supplied modal or polymorphic result type must reach the child check.
The skeleton pass leaves a ghost result and defers the child check. The full
pass checks the child against a supplied result, requires `Abs`, and exports
the result and thunk annotations together. Instantiate the canonical
`spawnWait` with those exported types. The supplied result has already been
checked, so the generated call does not repeat that subtype check.

`haveMail` retains its legacy mailbox requirement from `() {:_|_}~> Bool`:
its contextual type requires `Wild, Receive(a)`. JavaScript polls the current
mailbox; the interpreter retains its existing unsupported-server error.
`spawnWait'` remains private to the interpreter's continuation that retrieves
a completed child's result; it is not a contextual source primitive.

D7c1c migrates the full message suite and actor cases in the function,
polymorphism, continuation and typed-IR suites. Keep the mixed suites' feature
settings and select the contextual frontend for each migrated case. Closed
variant mailboxes use explicit signatures; open variant mailboxes infer their
shared payload from local receive functions in the child. Matching cases
execute both receives. Function aliases and receiver signatures state their `Receive(a)` requirement. The
continuation/mailbox counterexample uses a valid child mailbox context and
requires the diagnostic for capturing its contextual continuation across spawn.
The former source ended with an invalid semicolon and accepted any error.
The list-mailbox mismatch sends a list of strings before a list of integers;
this checks shared element types without an earlier String/List mismatch.

### D7 session integration

Keep session endpoints and access points classified by their protocols.
Input/output combines the message and continuation kinds; choice/selection
combines branch kinds. Access points follow the protocol kind. Existing
ordinary session linearity and unrestricted access-point use remain separate.

**Choice for review:** require message types in `send` and `receive` to have
`Type(Any,Any,Abs)`. A message crosses between processes whose effect contexts
may differ, as with actor messages. Modal functions and linear values may be
messages when their types satisfy `Abs`. Allowing arbitrary contextual
functions would need a rule relating the two process contexts.

Keep residual session parameters at `Type(Any,Session,Any)` for local primitive
calls. Requiring `Abs` for every remaining protocol would prevent local use
without a transfer. The existing absolute lock requires a complete protocol
to be absolute when its endpoint or access point is captured by a spawned
process; sending a channel as a message imposes the same requirement.
All session primitives retain their existing `Wild` effect. Exclude `cancel`
and session-failure support. Preserve existing runtime location restrictions
on client access points.

The first session execution audit found an existing interpreter close/link
failure: a sender can close its incoming buffer before a relay links the two
channels. `proc.ml`'s `close` removes that buffer, while `link` reads all four
buffers and raises `NotFound`. The same source fails on legacy and Fresco.
A request/acknowledgement exchange through the relay executes on both paths.
D8 must check and resolve the close/link case; the reproducer and both results
are in `/tmp/links-d7c2a-review-link-runtime.log`. D7c2a retains the runtime.
Migrating `examples/sessions/fusegg.links` reproduces the same failure after
successful source and IR checking (`/tmp/links-d7c2e2-examples-initial.log`).
Keep its immediate close/link order; D8 owns the runtime repair.

Stage `EndBang = !().End`, `EndQuery = ?().End`, `wait`, `closeBang`,
`makeEndBang` and `linkSync` in the contextual prelude. Their signatures require
`Wild`. `wait` receives unit and closes; `closeBang` sends unit and closes.
`makeEndBang` creates a peer that waits for that unit. `linkSync` links the
supplied endpoints and returns a fresh `EndBang`; its protocol parameter
retains `Type(Any,Session,Any)`. These ordinary session operations require no
session-failure annotation or control-flow-linearity construct.

**Choice for review:** give spawned callbacks in `fork`, `linFork`,
`reproduce`, `connect`, `forkSync`, `linForkSync` and `runSync` an absolute
`modal [Wild]` type. Use linear callback arrows for the `lin` variants. Their
protocol parameter has `Type(Any,Session,Abs)` because the access point or
endpoint crosses a spawn lock. The caller-side callback in `connect` remains
contextual. Preserve the legacy unlimited result parameter of `connect` and
unlimited message parameter of `runSync`; the latter also requires `Abs`.
These signatures cover the specialised ordinary-session uses. General
interfaces with independently chosen callback effect contexts remain deferred.
A spawned callback may install its own handlers.

**Choice for review:** require `Wild` for session selection and offer. Legacy
source checking omits this requirement, while the IR checker requires it.
The contextual rule agrees with the session primitives and the recorded
regex migration choice. Keeping the legacy source rule would require removing
the IR effect requirement. Contextual IR checks use scoped `Wild`, return the
selected continuation, and check offered branch continuation and result types.
A baseline program selecting `Go` and then receiving an integer executes with
IR checking disabled; the legacy checker reports the original channel type
where the input continuation is expected. The command and result are in
`/tmp/links-d7c2b-selection-baseline.log`.
Duplicate offer labels retain the last branch, as in the existing
`CompilePatterns` map construction. Check every written branch's result and
ordinary usage before lowering. Preserve checked outer variant and continuation
annotations. The legacy duplicate/annotation execution probes are in
`/tmp/links-d7c2b-review-legacy-patterns.log`.
Nested selection exposed another contextual IR comparison issue: existing
runtime dual construction can retain a dual flag on a closed row tail while
Fresco removes it. Contextual row equality ignores that flag when both tails
are closed, after comparing their fields. Open-row dual flags and legacy IR
equality remain unchanged.

Recursive offer checking must canonicalise both row roots before consistency,
as ordinary type joins already do. Extracting continuations can retain separate
checked copies of the same recursive declaration. Validate every declaration
copy and require matching bodies before sharing its identity. The recursive
`Loop = [&|Again:Loop,Done:End|&]` example exposed a conflicting-declaration
error when row joins skipped this step. Conflicting bodies still reject.

### D7 CP integration

Check CP using ordinary blocks, session operations and angel spawn. Direct
CP inference rebinds channel continuations and removes consumed channel names;
small source expansions supply split-end operations and composition. Private
primitive bindings refer to the runtime's
canonical primitives; source bindings cannot replace generated session calls.
Expand the split-end operations locally and use structural `!().End` and
`?().End` annotations, so CP needs no prelude or source type alias.

Grab and give rebind the channel to its continuation. Give evaluates the
payload before that rebinding. Selection and offer reuse their checked source
constructs. Empty grab waits and closes; empty give sends unit and closes.
Give-nothing checks and returns `!().End`. Link consumes dual endpoints and
returns a fresh split sending end. Composition creates an access point,
spawns an angel child for its left process, closes that process's split sending
end and binds the dual endpoint for the right process in the caller context.
Keep the existing `Wild` requirement and `endbang_antiquotes` setting.
The parser produces give-nothing for `c[]`; its retained internal empty-give
constructor is covered by a syntax-tree test. Skeleton inference supplies the
fixed split-end result of link and give-nothing, then full inference checks
the channels and their use.

The existing typed CP pass sets the first link binder twice, and its transform
reports a unit result for link. The contextual translation uses the two written
channel names and the split sending result directly. It shares the ordinary
session and actor rules, including endpoint use and absolute child captures.

### D7 session migration inventory

Preserve feature settings in the ordinary `sessions` suite and the session
cases in `modules` and `freezeml`. The two Freezeml cases now run their source
files; their old entries passed file paths as expressions. Remove the stale
Mono/Session ignore after checking both intended polymorphic-inference
failures. Supply the channel shape and the absolute message wrapper, leaving
the shared inner function type unknown. The first order rejects the initial
polymorphic demand; the second accepts a monomorphic use and rejects the later
polymorphic demand. Explicit `Identity` payloads provide a positive control
for both orders. Session signature checks display all quantified binders;
ordinary feature settings remain unchanged.

Migrate the remaining examples in bounded groups. The user deferred socket
examples, XML/forms and FFI/function locations on 7 November 2026; the
[future TODOs](../PLAN.md#future-todos) now govern those groups and their
dependent migrations.

| Group | Sources under `examples/sessions` | Check |
|---|---|---|
| Ordinary protocols | `calc`, `calc-cp`, `calc-endbang`, `end`, `fuse`, `fusegg`, `givengrab`, `linear_if` | Preserve types and run terminating examples; retain the recorded close/link failure for D8 if reproduced |
| Recursive/generic protocols | `atm`, `choice`, `reccalc`, `sim-calc`, `state`, `forkbomb`, `pi`, `two-factor`, `chatserver/frescoLinearList`, `mind/frescoLinearList` | Sign recursion and callbacks, preserve kinds; execute terminating local programs |
| Socket models | `smtp`, `smtp-end`, `smtp-factored`, `smtp-factored-more`, `smtp-dummy`, `Elvina/SMTP_Real_CP`, `Elvina/SMTP_Real_GV`, `Elvina/IRC_Test` | Deferred: typecheck socket clients and execute the local dummy model when resumed |
| XML/location prerequisites | `ap-multi-client`, browser calculators, bookshops, draggable examples, `gng-client`, `smtp-formlet`, `Elvina` web models and IRC, `mind/mindClient` and its `mindSessions` module | Deferred with XML/forms and function locations |
| Excluded or already broken | Session-failure chatserver trio and `mind/mindServer`, `two-factor-cp`, ignored `counter` and `draggable-boring` | Preserve exclusions and recorded ignore reasons |

The CP calculator, fusion and give/grab examples migrated in D7c2d. The
`forkbomb` file defines its infinite computation without invoking it. `state`
invokes an infinite computation; retain its typecheck-only use. Real SMTP/IRC
clients retain typecheck-only checks. They send messages to external services.
The ordinary session examples may need modal annotations on function messages
and explicit polymorphic/recursive signatures. Record specialised callback
contracts separately from interfaces needing independent effect contexts.

**Choice for review:** the encoded choice example sends `modal [] [|r|]`.
A rigid open row has no absolute-payload guarantee. Wrapping the transmitted
variant preserves its open-row interface and satisfies the existing absolute
message rule. Closing the row would lose that generic interface; adding
absolute row constraints would extend the language. The `off` callback remains
contextual and its result remains unlimited with modal kind `Any`. Checks under
a caller-installed handler cover both direct effects and returned contextual
functions. The selector's residual row keeps its original unrestricted field
category, including a non-session `B:Int` branch.

**Choice for review:** stage `frescoLinearList.links` beside each existing
`linearList.links`. The session-failure servers still use the legacy frontend
and import the original module; changing it made both server checks fail.
Fresco clients use the staged module when their migration is resumed. Migrating
the session-failure servers would expand the current scope. Retain the two
legacy modules until that separate feature migration.

The two staged `LinList` helpers retain ordinary `Any` payloads and contextual callbacks
over protocols with modal kind `Any`. Legacy controls accept `End` endpoints
inside these lists; explicit parameter kinds preserve that support. A checked
execution visits two endpoints under a caller-installed handler and then closes
both endpoints.

The State cell interface keeps `newCell` and `swap` generic over linear or
unlimited absolute payloads. `get` copies the payload and `put` discards the
old payload, so both require unlimited absolute payloads. The looping example
supplies its `modal [Wild] (() -> ())` payload type explicitly. Import-based
bounded checks use the actual definitions; the module loader omits the final
phrase, which invokes `forever`.

The process encoding retains the fixed `Wild` context of its original
`{}~>` arrows. Its delayed callbacks and `Proc` values use `modal [Wild]`.
Callbacks may install their own handlers. A caller's handler does not enter
that fixed context. The authentication example retains a contextual caller
callback in `serveData` and a modal-kind `Any` continuation in `Checker` and
`reportError`. Keep the recursive duality example's raw `mu` types and check
its definitions without invoking its infinite computations.

### D7 prelude prerequisites

Check each remaining argument group of a curried function through ordinary
term inference. This applies a supplied modal or quantified result type before
checking the next lambda, as for an explicit nested lambda. Calling the lambda
checker directly skips those introduction rules. Preserve the existing
parameter-name checks, ordinary capture checks and ambient-effect scopes.
Session example migration exposed this gap when a pure first stage returned
a `modal [Wild]` function.

Library migration exposed two frontend gaps. Skeleton inference checks a
sequenced expression against a ghost; the full pass still requires unit and
checks its effects. Supplying a concrete unit expectation during the skeleton
pass rejected effectful callback statements. Resolve frozen variable names
through the same module scope lookup as ordinary variable names, preserving
opened-module names and shadowing.

### D7 prelude migration

Stage the checked prelude in `lib/stdlib/frescoPrelude.links` while the legacy
frontend remains the default. Tests import this module through the normal
module loader. D7e will make the migrated definitions the default prelude and
remove the temporary duplication.

Give collection helpers explicit polymorphic signatures. The implicit global
`modal []` guard leaves their callback arrows contextual, so `map`, `iter`,
filters and folds use the caller's effects. Keep existing `Wild` contracts on
`sortBy` and `zip`, and require `Wild` for helpers calling partial primitives.
Ordinary kind requirements still reject linear list elements, duplicated
linear callbacks and discarded linear callback results. Signed local recursion
retains its surrounding type variables. The staged `intRange` uses the same
equality-stop correction as range syntax.

The remaining core prelude keeps the `Maybe` alias's ordinary `Any` parameter
kind, explicit `Wild` signatures for search and partial/association helpers, numeric
empty-list seeds and association-list ordering. `removeAssoc` removes the first
matching entry; `assocAll` keeps all matches in source order. Preserve the
existing regular expressions used by `isInt` and `isFloat`.

Migrate tuple projections with open ordinary record rows so they retain their
behaviour on larger tuples. Their selected field, and the type parameters of
`id`, `flip`, `uncurry` and `compose`, retain ordinary kind `Any` where the
legacy helpers accept linear values. The discarded projection row remains
`Unl`. Keep `mapi`'s element parameter `Unl`, as required by the existing
`Types.list` constructor. Its legacy printed type leaves that variable at
`Any`, but actual calls over nonempty linear lists reject.

Preserve explicit legacy `Wild` contracts and the requirements of partial or
external primitives. Pure helpers with exhaustive cases may have pure
contextual signatures even when legacy inference included `Wild` through
their switches or recursive calls. Preserve the existing `span` complete-match branch,
which returns its accumulated prefix in reverse order, and the resulting
`takeWhile` behaviour. This migration does not change those library results.

**Choice for review:** the staged `curry`, `flip`, `uncurry`, `compose`, `lf`,
`-<-` and `->-` use contextual arrows sharing the caller's ambient effects
through closure
construction and later calls. Their general legacy contracts permit an
independent effect context for callbacks and returned calls; those contracts
remain in the
[independent-effect audit](#signatures-with-independent-effect-variables).
Alternatives include separate helpers for fixed absolute callback contexts or
requiring explicit wrappers at each use. Test effectful calls and returned
closures so the specialised interface retains its stated effect requirements.

`Either` and `Maybe` aliases require explicit ordinary `Any` parameters.
Actual legacy prelude controls accept endpoint payloads in both aliases.
Leaving their contextual alias binders unannotated narrowed them to `Unl`;
D7d3b restores the original alias contracts. The function signatures of `pureE`,
`applyE` and the existing Maybe helpers retain their separate unlimited payload
requirements. `Pid` follows `Process` with an ordinary `Any`, absolute message
parameter, including linear endpoints.

Keep `lf`, application `$` and the composition operators' ordinary payload
parameters unlimited, matching their original signatures and accepted calls.
The existing `id`/`compose` family's ordinary `Any` parameters do not imply
that these separate interfaces accept linear payloads. The result of `lf`
remains a linear function and must be consumed once.

### D7 ordinary library inventory

After the collection and session helpers, migrate the remaining ordinary
helpers in small groups. The source audit is recorded in
`/tmp/links-d7d3-inventory.md` at revision `8b27a80b`.

| Group | Sources and completion checks |
|---|---|
| Lists, characters and dates | `elemIndex`, `partition`, `groupByFlat`, ASCII predicates/conversions and UTC/local wrappers; preserve list ordering, callback effects and explicit `Wild` contracts |
| Other ordinary helpers | List grouping helpers embedded in mixed prelude sections, Maybe helpers, ordinary aliases and composition operators; record independent-context interfaces separately |
| Trees | `binaryTree.links`, `comparators.links` and the five binary-tree cases; preserve algorithms and test contextual comparison callbacks |
| Ordinary examples | Church numerals, extensible cases, recursive bit lists and switch functions; execute bounded results and retain polymorphic/row requirements |
| Ordinary actor examples | Buffered channels and console helpers; check bounded message ordering and callback contracts |

`elemIndex` retains its first-match result and explicit `Wild` requirement.
`partition` retains its explicit `Wild` requirement and reverses each output
list, while its predicate uses the caller's effects. `groupByFlat` retains a
group for every source item, including duplicate keys, and repeats its projection
calls in the existing order. ASCII helpers and UTC accessors remain pure;
local accessors retain their written `Wild` contracts, except the existing pure
`localMilliseconds` helper.

The binary-tree alias retains ordinary `Any` payloads: legacy manual nodes
accept endpoints. Its function signatures retain their separate unlimited
payload requirements; legacy `empty` and `invert` reject endpoint instantiations.

**Choice for review:** give `leftmost_child` the same contextual comparator
interface as the other tree helpers. The existing body never calls its
comparator; its general legacy signature permits independent comparator and
caller effects. A legacy control passes a `Ping` comparator without a handler
and returns the leftmost node. The specialised interface requires the callback's
effects in the caller. Its general interface remains deferred in the
[independent-effect inventory](#signatures-with-independent-effect-variables).
A whole-type parameter for the unused argument would also accept non-functions;
a fixed modal comparator would select one callback context. Preserve the body
and check that the callback remains uncalled. Legacy evidence is in
`/tmp/links-d7d3c-legacy-unused-callback.log`.

Supply a nominal tree annotation for direct structural `Node`/`Leaf` values
when generic helper application cannot infer that recursive shape. Existing
fixtures establish it through `empty()`. This follows the staged recursive-list
constructor migration. Ordinary payload refinement is checked by subsequent
accepted and rejected calls; a raw variable's declared kind does not expose
its retained requirement.

The tree deletion example's existing two-child branch duplicates the left
subtree. Preserve the recorded `remove2` result during type migration.
Switch-function syntax already passes through `DesugarSwitchFuns` before
Fresco inference. Its internal unsupported-node guard does not establish a
source-language gap. The generated final case calls `error`, so every switch
function retains `Wild`, including exhaustive matches. Preserve the default
unlimited input binder on the polymorphic identity example. The migrated suite
keeps `switch_functions=true` and its original seven cases; added strict-IR
controls exercise named/anonymous polymorphism, nested bodies, filename/line
reporting, unavailable `Wild` and rejected endpoint inputs. Empty switches use
the separate rule below when migrating extensible cases.

**Choice for review:** the Church numeral example uses
`Nat = modal [] (forall a. (a) -> (modal [] ((a) -> a)) -> a)`.
The numeral and step function remain pure. Its intermediate function is
contextual, so `zero` can retain its seed of ordinary unlimited, modal `Any`
type `a`. Giving that intermediate function an absolute modality rejects this
capture; requiring `a::Abs` would narrow the seed type. The selected interface
retains contextual seeds and specialises the legacy fixed-pure intermediate
function contract. A bound `two(seed)` can be called in its current context;
capturing it in a fresh absolute function requires an absolute wrapper or
construction inside that scope, including when the seed is an integer.
The absolute step also rejects a closure that captures a contextual seed;
a pure identity step can still pass that seed through. Legacy fixed-pure
arrows permit the former capture. The selected comparison is in
`/tmp/links-d7d3d2-review-legacy-step-capture.log`.
The alternative all-absolute signature and successful numeral execution are in
`/tmp/links-d7d3d2-church-fixed.log` and
`/tmp/links-d7d3d2-church-shared.log`.

**Choice for review:** the extensible-case example's curried helpers use a
shared ambient context for construction, callbacks and returned calls. The
legacy signatures permit separate construction effects. Preserve those general
contracts in the [independent-effect inventory](#signatures-with-independent-effect-variables),
as for the curried prelude helpers. Fixed modal callback contexts would select
particular effects. Keep `add_A`/`add_B`/`add_C` residual rows at ordinary `Any`,
`defaultCase` and `sub_A` residual rows at `Unl`, and `sub_A`'s added payload at
`Unl`. Write the ordinary `Any` row kind in full as `Row(Any,Any)`:
`Row(Any)` follows the existing effect-row shorthand, whose linearity is
unlimited when control-flow linearity is disabled. The results of `nocases`
and `sub_A` retain ordinary `Any`.

The bit-list example retains all written `Wild` contracts and a contextual
`zipbits` callback. Keep the empty-left branch's `f(y, false)` argument order
and the local conversion loop's call to `intToBits`. Bounded conversions,
unequal padding, callback order and the finite renderer execute through the
actual module. All 1,024 rendered cells match `(i & j) == 0`; the check is in
`/tmp/links-d7d3d2-renderer-check.log`.

The buffered-channel example keeps `Channel(a::Any)` as a pair of fixed
`modal [Wild]` read/write functions. `newChannel` requires `a` to be unlimited
and absolute: its queue is a list and its messages cross actor boundaries.
Legacy checks accept the alias at `End` and reject the queue constructor at
`End`. `get` and `put` keep unlimited, modal `Any` payload parameters; they
invoke supplied functions and add no message restriction. Preserve queue
ordering, reader ordering and the existing non-terminating queue actor. Bounded
tests use the actual imported module. The waiting-reader fixture uses a bounded
300-call loop to yield before the write; an empty `spawnWait` can return without
yielding. The selected debug trace confirms the queue receives `Read` and the
reply process blocks before `Value` is sent:
`/tmp/links-d7d3e1-review-waiting-trace.log`. Replace the legacy mailbox-effect casts
with modal function calls and supply the mailbox type to `self` explicitly.

**Choice for review:** defer the remaining `TicTacToe-Console.links` migration.
Following the user's concern about peripheral work, prioritise prelude loading,
batch/REPL integration and the default contextual frontend. Existing ordinary
function, polymorphism, data-structure, effect and actor checks cover the core
language readiness needed for that transition.

Keep XML/formlet/page/DOM/routes, MVU modules, socket examples and explicit
foreign/location dependencies with the deferred features. Keep database-facing
Serial helpers and session-failure monitoring outside this work. General
`Comp`/`gen0`/`gen1`/`gen2` effect-row interfaces remain in the independent-effect
inventory.

**Choice for review:** defer the root prelude's `State`, `runState`, `>>=`,
`return`, `fmap` and `sequence` with the formlet library. Their current uses
belong to that library. A legacy control captures a contextual `Get` function
in `return`, runs the state computation, then handles and invokes the returned
function to produce `42`. Making `State` an absolute `modal [Wild]` type requires
`Abs` captures and rejects that call. Making its arrow contextual changes the
original fixed-`Wild` contract. Preserve the contract for the deferred migration;
the audit and controls are in `/tmp/links-d7d3b-state-contract.md` and
`/tmp/links-d7d3b-state-controls.log`. The monadic-reflection example defines
its own state helpers and separately depends on general independent-effect
interfaces.

### D7 empty switches

Preserve the legacy partial-match behaviour of an empty switch. Its scrutinee
may be an empty variant, an inhabited type or an unknown type. Legacy checking
adds no scrutinee constraint when there are no cases; actual inhabited and
integer executions fail through `Wrong`. Ordinary partial Fresco switches
already behave the same way without an additional `Wild` requirement.
Restricting empty switches to empty variants would narrow ordinary Links
behaviour. The legacy controls are in `/tmp/links-d7d3d0-legacy-*.log`.

Use the supplied result mode, or retain an unknown result type when inferring.
Preserve quantified and modal introduction rules and ensure full checked terms
contain no ghosts. Keep conservative ordinary usage: an unrelated unused
endpoint remains an error, while consuming it before the switch is accepted.
The existing lowering evaluates the scrutinee through a let binding and compiles
zero cases to `Wrong` at the result type. No backend change is required. An abort
operation returning the empty variant provides a bounded execution check that
handles the operation before the match failure is reached.

### D7 explicit upcasts

The extensible-case example widens an explicitly absent variant case. Ordinary
Fresco consistency correctly keeps field presence invariant; an explicit
upcast needs a separate structural check. Share that check between source
upcasts and contextual IR coercions. Keep ordinary inference, consistency and
modal subtyping unchanged. Preserve contextual equality for types outside the
structural width rules; do not introduce a separate recursive-variance algorithm.
`FrescoUpcast.check` expands stored solutions, validates ghost-free types and
proves the relation without assigning variables or refining requirements.
Aliases expose their bodies; modalities, quantifiers, abstract types, sessions
and recursive types use checked equality. Function domains must be closed tuple
rows with equal argument counts. Normalising a solved row tail preserves outer
field masks. Missing fields under an unresolved tail remain unknown.

The legacy comparison found four defects to avoid copying. Its row-field fold
can overwrite an earlier mismatch, record narrowing can hide an endpoint,
removing an explicit field can expose a conflicting field in a shared open tail,
and function-domain record narrowing can change arity. The reduced cases are in
`/tmp/links-d7d3d3a-review-legacy-controls.log`. Check every field, require hidden
record resources to be unlimited, treat missing fields under an open tail as
unknown, and compare equal-length argument lists contravariantly. Retain arrow
linearity and check results covariantly. Upcasts erase at runtime, so they cannot
implement argument adapters or dispose of hidden linear resources.

The source expression must first satisfy its written source type. Check both
annotations through contextual elaboration, preserve ordinary usage and modal
capture rules, and emit a coercion with the written target type. Contextual IR
must validate that same relation after runtime type conversion. Accepted and
rejected tests cover both boundaries, including the four legacy defects.

### D7 frontend integration plan

The frontend audit at `8b27a80b` is recorded in
`/tmp/links-d7e-inventory.md`. First separate checked preparation from execution,
then add default/custom prelude loading, REPL directives and JavaScript output.
Switch the default after the ordinary source migration checks pass. Retain
explicit legacy access for deferred and excluded fixtures until D8; never
fall back to legacy after a contextual type error.

The contextual frontend now checks typed lowering and retains operator
fixities and loads the configured prelude as described below. Complete REPL
and compilation integration before the default switch. Preserve module identities across
prelude loading and later imports. JavaScript compilation needs the preceding
prelude bindings as well as the current source's IR, without evaluating the
source program. Existing shared backend generation remains the implementation.

**Choice for review:** make frontend rechecking validate the complete contextual
IR immediately after typed lowering, including its result type. This is the
common boundary after generated comprehensions, pattern compilation, scoped
handlers and runtime type conversion. Earlier source expansions already pass
through full Fresco inference. Preserve the filter/dump settings and keep
backend checks after optimisation and closure conversion separate.

Checked preparation is separate from execution in `FrescoFrontend`.
A prepared value contains the next inference/name state, prior runtime values,
lowered IR, source result type, prior type environment, effect declarations and
ambient row. Preparation and compilation do not evaluate source code;
`run_prepared` evaluates and returns the published state. Keep `empty` limited
to primitives for unit tests. Prelude loading and REPL snapshots remain separate
integration steps.

The `fresco-lowering` check uses the existing frontend flag, newline-separated
filter and failure-dump setting. Its strict IR entry checks all internal
annotations and the result against the source's runtime type. Strictness is
passed through the checker's local recovery sites; it does not change global
settings. The existing backend checker retains its warning behaviour. The
selected frontend check raises even when `typecheck_ir` and
`fail_on_ir_type_error` are false. As with legacy frontend dumps, diagnostic
dumping requires debug output. With this checkpoint selected, `check_string`
and `check_file` also lower and check IR without evaluation; otherwise they
retain source-only checking.

Persist the immutable shunting operator table in `FrescoInfer.t`, beginning
with the existing defaults. Each input uses a local shunter; only successful
checking returns a state containing its updated table. Failed preparation and
check-only calls leave the caller's table unchanged.

String parsing already reads `Parse.pp`. File preparation now uses
`Parse.parse_file` so preprocessing retains the file's source name and
positions. Its unprocessed-file branch uses `call_with_open_infile`, preserving
the deterministic channel closure previously provided by the Fresco wrapper.
No parser grammar or preprocessing command semantics change.

**Choice for review:** an unset `prelude` setting selects the frontend's
default: the root `prelude.links` for legacy checking and canonical
`open import FrescoPrelude` for contextual checking. Explicit paths override
either default, including the existing empty-prelude file. Install the
contextual module with the standard library and use existing path discovery.
Opening the same module later must reuse its declaration identity.

Prepare the bootstrap before processing user input. Interpretation evaluates
that prepared bootstrap once and suppresses its result. Typecheck-only mode
uses its checked state without evaluating it. The checked-state accessor has
no new runtime values and is for checking, preparation and compilation;
interpretation must obtain its state by running the prepared bootstrap.
Retain the prepared bootstrap IR for the later JavaScript compilation step.

**Choice for review:** bootstrap preparation always lowers the prelude, also
in typecheck-only mode. A custom prelude must satisfy lowering extension guards
even when the user-program frontend-recheck filter is `none`. This preserves
one prepared module identity without introducing a second source-only bootstrap
state. Keep the existing first-input exit for typecheck-only mode in this
milestone. Normal batch isolation and expression-before-file ordering remain.
Use the existing `--set=fresco=false` for explicit legacy selection. A separate
`--legacy` flag would make selection depend on registration order in Settings;
keep one frontend setting.

The contextual REPL uses `FrescoFrontend` for sentences and `@load`, with the
existing value printer, welcome text and setting controls. Definitions print
only new or replaced bindings. Compare runtime variable identities for values
and private immutable alias records for aliases before exporting their types.
Export displayed types from the current contextual solutions into detached
graphs; displaying or inspecting an environment must not modify live inference
state. Named functions use the existing function-table lookup when their runtime
environment contains no value entry.

`@env`, `@typeenv`, `@tyconenv` and `@builtins` use these contextual snapshots.
Successful loads publish their state and retain module identities. Parse, type,
load and interrupt errors retain the last successful state. The interaction loop
restores the previous signal handler on exit. Contextual `@withtype` elaborates
and matches queries in isolated inference state.

**Choice for review:** `@withtype T` searches for values that can supply the
query type `T`, using contextual subtyping from each candidate to `T` under the
current ambient effects. Candidate polymorphism may instantiate; an explicit
`forall` in `T` remains a requirement. Elaborate queries using current aliases
and ordinary annotation rules: a named `a` is rigid and `%a` is flexible. The
alternative is a separate symmetric query relation matching legacy unification;
using contextual subtyping keeps search consistent with source use sites.
Each candidate starts from the same persistent query context and discards its
resulting context. Search neither refines live unknowns nor shares refinements
between candidates. Include primitives and user definitions. Display each
match's current type without applying solutions from the search.

### D7 inferred linear results

**Choice for review:** retain the ordinary-arrow guess for unresolved callable
types. A callback or result annotation, or an intermediate binding, is required
when this guess would otherwise conflict with a later linear-arrow result.
For example, with `apply : forall a::Any,b::Any. ((a)->b,a)->b`,
`apply(fun(x){x},linfun(){42})()` rejects. Binding its inner application to
`k` and then calling `k()` succeeds, as does supplying the callback parameter
type or annotating the inner result with `() -@ Int`.

`FrescoConstraints` extracts an ordinary arrow from a ghost under `Fun` mode.
The callback skeleton can leave its parameter and result as separate ghosts,
so that arrow choice can precede information from the full callback check.
This applies to general function application as well as the staged helpers.
Keep the helpers' `Any` parameters, which admit the supplied linear types.

The skeleton abstraction discussion in the thesis'
`chapters/maetel/algorithm.tex` explains why skeleton lambda parameters remain
ghosts: a later check may supply polymorphic types. Sharing
fresh monotype variables would lose that behaviour. Deferring callable modes
requires retaining their polymorphic and modal information and checking the
obligations after argument inference; retrying full inference requires restoring
contexts, usage counts and scoped evidence. Both alternatives require further
inference design. Independent design review selected the annotation/binding
requirement for this migration. No inference rule or backend code changes here.

### D7 continuations

`FrescoInfer` obtains the continuation argument type from a supplied expected
type or a skeleton pass over the escape body. This preserves supplied
polymorphic and modal result types. The continuation call result uses one
fresh monotype variable. The body result must agree with the continuation
argument type. A scope marker exports the body, continuation type and ambient
row together. Ordinary usage checks apply to the body and its free variables.
Lower the checked expression to the existing `CallCC` IR operation with a
local function binding. The interpreter and JavaScript backend retain their
existing implementations.

Give the continuation a contextual arrow tied to its capture context. Modal
access checks then preserve the context of its argument and result types.
An absolute `modal [Wild]` guard loses this relation: a continuation called
inside an added handler could carry a callback using that handler's effect
out of its scope. A review probe reproduced the resulting unhandled operation.

**Choice for review:** use the existing contextual-arrow access rule for
continuations. Calls across an added handler reject even when the argument is
`Int`; capturing the continuation inside an absolute modal closure also
rejects. This retains contextual function results without extending the
modality rules. An alternative is to require absolute continuation arguments
and permit more changes of context, which would exclude those function results.

Preserve the single inferred continuation result type used by
`TypeSugar.Check`: its comment discusses result polymorphism, but its rule
does not implement it. Uses returning both `String` and `Bool` therefore
reject. Capturing the continuation also requires ambient `Wild`.

### D7 ranges and list comprehensions

Keep checked range, concatenating-map and sorting nodes with their ambient
rows among the inference roots. Lower them to local typed recursive helpers.
Primitive references in these helpers use runtime identifiers. The contextual
frontend can therefore execute these constructs before prelude migration.

**For user review: compiler-owned comprehension helpers.** Source bindings
named `map`, `concatMap`, `sortByBase` or `intRange` do not replace these internal
helpers. This gives the syntax a checked implementation before the prelude is
available. The alternative is to resolve and check helper calls through the
source environment, retaining a dependency on those bindings.

Retain supplied polymorphic and modal list element types. A guarded collection
keeps its checked type, and each extracted element receives the collection's
guard, following list pattern checking. Returning an extracted function keeps
that guard; invoking it requires the corresponding ambient effects.

Comma-separated generator expressions use the outer environment. Their
patterns become available to the body, filter and ordering expression together.
Use nested comprehensions when a later generator depends on an earlier binder.
Repeated names across generator patterns retain the first binding, as in Links.
Later occurrences receive private names during checking and lowering. Generator
source expressions keep their outer bindings when a pattern shadows a name;
this corrects a legacy mismatch between source checking and later desugaring.
Build the full Cartesian product before sorting and then filtering/evaluating
the body. Later generator expressions run once per preceding combination.
Preserve `sortByBase`'s two partitions and repeated key calls: sorting
`[2,1,3]` with a key that prints its argument prints `12321232`.

Ranges are inclusive and descend from the upper bound while building the
result. Stop when that bound equals the lower bound before subtracting one.
This corrects the old `intRange` overflow at a singleton `min_int` range.

### D5/D6 source and runtime boundary

Use an opt-in `--fresco` entry point with a small primitive environment while
the default frontend awaits D7. Keep inference state persistent between
interactive definitions. Publish updated type and name-resolution state only
after checking succeeds. The source tests must exercise retained unknowns and
failure recovery through this entry point.

The `typecheck_only` setting checks file and `-e` inputs without lowering or
evaluating them. Reject this setting before reading interactive input. Signed
recursion adds no `Wild` requirement, following the reference implementation.
Top-level usage checks retain existing Links behaviour.

Keep source types, annotations and exported inference state in the contextual
representation. Lower checked terms to the existing Links IR and use its
backend and interpreter. In the runtime type view, erase modal wrappers and
retain contextual arrows, quantified structure and quantifier metadata.
Modal access and instantiation requirements are checked before this erasure.
IR checks still compare function domains, results and explicit type operations.
D6 must carry the scoped-effect information needed to check operations and
handlers; legacy operation-row sets cannot represent repeated effects.

Validate each exported recursive declaration snapshot under its formal
parameters before merging snapshots with the same nominal identity. Compare
their representations and reject conflicting bodies. Build private runtime
copies with structural substitution callbacks; source declaration callbacks
remain contextual. Runtime coercions require a contextual subtyping proof and
preserve the evaluated term. Recursive IR comparison uses contextual equality
on this path. Previous interactive globals and published definitions remain
available through optimisation and closure conversion.

The source inference passes share a typed term representation. Preserve every
annotation as a root when leaving a scope, including explicit type arguments,
ambient effect arguments and lock arguments. Restore the roots returned by
scope exit before using the reduced context. The skeleton pass supplies
information for application inference; only the full pass counts term uses.

Source testing exposed a restriction in directional equality extraction:
when a universal ghost acquires a quantifier supplied only by the right-hand
type, its ordinary ghosts may refer to that new binder. Retain the quantifier
in the output, following `SolE-GhostForall` in the thesis. Continue forbidding
capture under quantifiers already enclosing the left-hand ghosts. This uses
the same distinction between the two sides as consistency. The corrected
case accepts `choose(id)` checked at a function from a polymorphic identity
to a polymorphic identity. Direct tests retain the rejection of a ghost under
an existing binder being filled by that binder.

Function mode describes an application and accepts both ordinary and linear
arrows. Retain the source arrow's linearity in its output. `LinearFun` also
requires a linear arrow, and checking against a written arrow still compares
linearity. This permits applying a linear function returned by polymorphic
identity without repeating source inference. Runtime coercion checks compare
the resulting arrow with the requested target, so this application rule cannot
convert a linear function into an unlimited function.

Direct record and tuple fields retain independently inferred types. Reference
examples using polymorphic nominal constructors are tested with an equivalent
polymorphic helper application; replacing such an application with a direct
Links tuple can change where supplied quantifiers are retained.

List literals and list patterns impose `List`'s declared parameter requirements
on their element types before constructing or checking the application. Fresh
element unknowns acquire those requirements; other fresh unknowns keep their
ordinary defaults.

### D6 scoped effects in IR

Keep contextual operation and handler nodes separate from legacy nodes. An
operation retains its resolved identity and selected effect application. A
handler retains its handled singleton row (or an empty row for a return-only
handler) and outer row. Contextual function definitions retain their ambient
row after runtime modal wrappers are erased. These rows preserve repeated
occurrences and their type arguments through optimisation and closure conversion.

Pass the checked declaration registry to the IR checker, including formal
parameters and every operation signature. Check an operation against the first
matching ambient occurrence. Check complete handler groups, clause argument and
resumption types, and the rows for the computation and clauses. Source inference
checks modal introduction and variable access before lowering; the IR retains
the evidence needed to recheck operation scopes and handler structure.

**Confirmed by the user, 7 November 2026: source-only modal checks.** Modal
access, modal call admissibility and effect-argument kind checks remain in
source inference. Keep runtime type erasure. IR checks operation identities,
effect occurrences, signatures and handler structure without repeating those
source checks.

Keep the existing `enable_handlers` feature setting for execution during D6.
The runtime selects its continuation implementation when the process starts;
changing the setting later cannot replace that implementation. Source execution
tests start a fresh CLI process with handlers enabled. D7 owns changes to the
default frontend and feature settings.

Reserve the source declaration names `Wild` and `Receive` in every module and
lexical scope. Their built-in identities are shared by annotations, the initial
ambient row and handler rejection. `Receive` has an absolute message parameter;
actor source support remains in D7.

Matching a guarded record, variant or list propagates its leading guard to the
bound fields. Projection preserves the same guard on its selected field and
checks that discarded fields are unlimited. This follows the thesis' pattern
splitting rule; extracting an absolute field can then remove its guard while
extracting a contextual function retains it.

Handler parameter initialisers use the outer variable environment. Parameters
are available in return and operation clauses; the handled computation uses the
outer variable environment. Deep resumptions take updated parameters after the
operation result. This follows `typeSugar.ml` and `sugartoir.ml`.

Join handler and branch result types separately from strict consistency used
for function domains and patterns. Compose each result's leading modalities,
join the payloads by consistency, then join the modalities using the ambient
row. Absolute rows use a union; relative extensions and removal masks use an
intersection, followed by checks from both input modalities to the result.
Match repeated effect occurrences from left to right throughout. This follows
the reference's `join` and `join_mod` rules in `lib/type.ml`.

An already absolute payload permits dropping the leading modalities without
effect equations. Variable use also removes a leading modality when its payload
is already absolute, including after crossing locks. This query does not refine
unknowns. Otherwise try their argument equations first. If they fail,
discard those equations and try payload `Abs` refinement from the context after
payload consistency. Successful equations remain committed. The skeleton query
treats ordinary ghosts as provisionally absolute; full inference repeats the
join after filling them. These are the same kind and matching policies used
by modal subtyping.

**Confirmed by the user, 7 November 2026: infer handler results from return
clauses first.** Join the return-clause result types, then check operation
clauses against that type, fixing the resumption result type before its uses.
A return result `modal [A] (() -> Int)` and an operation result
`modal [B] (() -> Int)` require an explicit handler result annotation
`modal [A,B] (() -> Int)`. The reference implementation applies modal join
across all clause results after typing resumptions.

### Contextual annotation and declaration elaboration

Reuse `DesugarTypeVariables` for source variable occurrences, ordinary kind
inference and defaults. Convert resolved syntax through contextual type
operations. Legacy `Instantiate.alias` removes leading quantifiers and cannot
apply modal aliases. Keep contextual conversion separate from the legacy
frontend until source inference is ready.

`FrescoElaborate` returns persistent context, alias, typed-effect and resolution
state. It exposes annotations, ordinary Type/Row/Presence arguments, written
function signatures and declaration groups. The source readers attach source
text before resolution so formatted errors retain their positions. Callers
with already resolved module names can use the same conversion path. The
variable resolver copies supplied descriptors into private points and avoids
IDs already present in the context or supplied source scope.

Check closure of every operation signature in an effect declaration before
resolving its variables. Reject unbound names, including flexible names, and
anonymous type, row and presence placeholders. Then introduce fresh rigid
parameters and a provisional self-effect descriptor. Publish typed operations
only after all argument and result checks pass. Keep source positions through
conversion and report the argument or result that fails its requirement.

Build named recursive declaration groups privately before checking their
bodies. Keep raw bodies and linearity callbacks stable after publication.
Compute ordinary linearity through contextual kind checks, starting recursive
flags at unrestricted and repeating until they stop changing. Legacy recursive
dependency collection scans children that need not contribute to linearity.
Keep cyclic groups nominal and acyclic aliases transparent. Recursive declaration
arguments, including unused arguments, retain the comparison rules recorded above.
Aliases may contain named flexible variables and anonymous flexible Type or
Presence placeholders, as in Links. Rigid anonymous placeholders and anonymous
row placeholders remain rejected. Resolve allowed unknowns in a fresh declaration
scope and retain them in the returned context across applications. Alias parameters
and variables do not capture enclosing source type variables. Operation signatures
remain closed.

**Confirmed by the user: implicit binders in written function signatures.** Preserve
Links' convention that named rigid variables in a written signature such as
`sig id : (a) -> a` supply quantified binders. This follows the instruction to
retain existing non-effect behaviour and keeps those names available to
annotations in the function body. Explicit `forall` binders retain their scope.
This choice does not generalise unsigned inferred types, flexible `%a` variables
or anonymous placeholders. The main alternative is to require explicit
`forall` in every polymorphic signature, which rejects existing signed
programs. Legacy evidence is in `desugarTypeVariables.ml`'s function/signature
visitor, `typeSugar.ml`'s signature generalisation, and
`tests/desugar_datatypes/nestedQuantifiers1.links`.

Insert a global function signature's default `modal []` inside its leading
quantifiers. Preserve an explicit absolute modality in the leading type
structure, including either placement relative to quantifiers. An absolute
modality in a callback type does not supply the outer function's default.
Local and expression annotations retain their supplied modalities.

**Confirmed by the user: closed ordinary braced row arguments.** Treat the parser's
synthetic `$eff` tail as closed when it comes from an ordinary braced Row
argument, such as `R({x:Int})`. Links accepts this as a closed row with
`effect_sugar=false`. With both legacy `effect_sugar` and its `open_default`
policy enabled, the shared grammar adds an effect tail even in this ordinary
Row position. Contextual types have
no such effect tails. Keep explicitly written row variables and reject explicit
anonymous placeholders in closed declarations. The alternative is to make
the synthetic tail an ordinary unknown row, which would allow additional fields.
Preserve Links' first-field precedence for duplicate ordinary row labels.
Elaborate and validate discarded fields too. Checks beneath authored recursive
types use the completed recursive body. A discarded field is checked separately
after closing its recursive references with the retained recursive types; its
enclosing ordinary quantifiers keep their original scope.

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

### Inferring handler effects and their arguments

Effect ownership is resolved before typing the handler. The existing resolver
already supports an absent handler annotation and selects the common owner of
its operation clauses. Preserve ambiguity rejection for unqualified short names
shared by different effects. Continue checking group completeness and ownership.

When no type arguments are supplied, allocate one fresh flexible Type variable
for each parameter of the selected effect. Preserve the parameter's ordinary
and modal requirements and use the same arguments for the handled computation,
operation signatures, resumptions and clauses. Solve monotype arguments using
the adapted unifier. Apply ordinary scope-exit and escape checks to surviving
arguments and handler results. An unused parameter can remain unsolved: discard
its unknown if no surviving type needs it, otherwise retain it with its kind
and scope requirements. Omission alone does not require an annotation.

Distinguish omitted arguments on a handler from a malformed explicit argument
list. Permit a name-only annotation for a parameterised handled effect; keep
arity checks for explicitly supplied lists and for effect applications in modal
types. The generic `effect_application` resolver requires full arity; the handler
path permits a name without arguments. Empty explicit argument lists fail
parsing, so an empty argument list in the handler AST means omission. Explicit polymorphic/modal
arguments go through annotation elaboration and Fresco checks. Test inferred
monotypes, explicit polymorphic/modal arguments, ordinary/modal kind failures,
shared clause arguments, unused parameters, qualification and ambiguous short names.

### Shared type and traversal contracts

`EffectRow.match_equal` and `EffectRow.match_subeffect` return ordered argument
pairs before payload comparison. `Modality.right_residual` uses the prefix
construction above. Implementation status and completion checks are in PLAN.md.

`Quantifier` stores variable identity, `Kind.t`,
and `ModalKind.t`; constructors default to `Any` and reject `Abs` on
row/presence binders. Copies retain both kinds. Structural substitution
preserves `Abs`; legacy inference and type application reject it.
Binder identity equality remains separate from full binder comparison.
Printers use the combined kind annotation when both ordinary and modal fields
need to be shown. Use `::Abs` alone only when ordinary inference/defaults
reconstruct the same kind. Preserve existing ordinary-only output where valid.

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
continuations. The opt-in contextual IR checker uses Fresco's recursive
comparison. Runtime copies provide structural raw-body application callbacks
for existing type consumers. Source inference and detached export retain
their separate contextual operations. The legacy IR path still rejects
recursive equality involving contextual arrows or modal types; its old
recursive equality shortcut remains confined to legacy programs. D8 audits
the remaining recursive consumers during migration.

At the runtime boundary, convert lexical `Recursive` binders and their bound
`Var` references to fresh recursive point graphs. The shared runtime visitors
refresh recursive binder IDs and follow point cycles. Leaving a lexical
reference unchanged during that refresh made `new():AP(mu a.!Int.a)` fail
checked IR with an unbound variable. Preserve free variables, mask quantified
binders, and normalise nominal declaration bodies in their independent scope.
Source types remain unchanged. The comparison rules need no relaxation.

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

`FrescoRecursive` applies formal arguments simultaneously and preserves supplied
quantifiers and modalities. Pure operations preserve ghosts. Checked operations
validate raw bodies under their formal binders and actual arguments against every
ordinary/modal requirement, including unused parameters. Detached callers restore
the exported variable table before checking. Session duality exchanges input and
output and selection and choice, while message payloads keep their original type.
Checked duality requires `Session`, including for nominal applications.
Pure skeleton duality preserves an ordinary ghost and dualises the body of a
universal ghost. A callback application can leave `Dual Ghost` before its
protocol is known; rejecting that skeleton prevents the full callback check
from supplying the protocol. Checked duality still rejects both ghost forms
through ghost-free conversion. Concrete non-session types retain their errors.

Represent a dual choice row using an empty row whose tail
is the original copied row and whose tail-duality flag is set. This retains
unknown presences and recursive rows without calling mutable legacy flattening.
Equality and consistency must interpret the deferred duality when comparing rows.

Legacy exported `r_unwind` callbacks still reject unfolding. Contextual operations
receive the environment and restored variable requirements explicitly. Installing
an ordinary callback would lose that metadata. Migrate consumers to the contextual
operations in D7/D8 before removing the temporary callback rejection.

The user selected Links' existing equality behaviour on 6 November 2026.
Transparent aliases compare through their bodies, including unused parameters.
For applications of the same recursive declaration, Links compares actual
arguments even when the body does not use a parameter. Distinct recursive
declarations compare through their bodies.

Selected source probes also found two defects in legacy comparison. Equal
applications with growing arguments can fail to terminate. The declarations
`P(a,b) = Leaf(a) | Next(P(b,List(b)))` and
`Q = Leaf(Int) | Next(Q)` are incorrectly accepted as equal at `P(Int,Int)`
and `Q`, in both directions. Their leaf types differ after two `Next` steps.
The legacy assumption cache can close a comparison after only the opposing
body repeats, while the first declaration's arguments have changed.

The user authorised a distinct “cannot establish recursive type equality”
error when a sound terminating comparison cannot settle a case. Preserve this
outcome separately from a proved mismatch. This temporarily rejects some equal
recursive types. A complete comparison algorithm is deferred; the new comparison
must reject the delayed mismatch above and test equal and unequal applications
whose arguments grow during unfolding.

Use read-only comparison with three outcomes: equality,
a structural mismatch, or unresolved obligations. Candidate equations replace
repeated argument subterms by shared fresh rigid variables while retaining
abstract constructor structure. Prove each equation by unfolding, allowing a
recursive assumption only under a checked constructor and one consistent
substitution across both applications. A failed candidate does not prove
inequality. Concrete comparison keeps complete argument pairs; repeated finite
summaries of argument heads stop further growth with an unresolved result.
This avoids a numeric unfolding limit. A complete decision procedure remains
the main alternative and is deferred under the user's decision above.

A current incomplete example is
`P(a,b) = Leaf(a) | Next(P(a,List(b)))` and
`Q = Leaf(Int) | Next(Q)`. `P(Int,Int)` and `Q` have equal unfoldings, but
comparison returns an unresolved result. The unused growing second argument
prevents the current candidate equations from proving this instance. Keep this
example when extending the comparison algorithm.

Proofs and assumptions belong to one comparison call. Flexible and ghost
obligations retain their lexical binders. Consistency solves applicable
obligations in a returned context and compares again; it cannot retain a proof
across changed assignments. Tests include regular recursion, growing and
shifted arguments, delayed mismatches, binder capture, rows and modality
arguments. Source probes establish legacy behaviour; these operations become
source-facing only after inference integration.

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
call the unadapted mutable unifier. Resolve existing solutions, check occurs,
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
require available declaration linearity metadata for an `Unl` check, then
classify the declaration body using the actual argument summaries. A generic
`Any` parameter can make the declaration's conservative linearity flag true
while its `Int` application is unlimited. Boolean summaries keep changing
recursive arguments finite; phantom arguments do not make unused payloads
linear, while concrete linear fields and used linear arguments do.

Keep the exported declaration-wide linearity metadata stable across application
substitution and detached snapshots. Existing contextual IR checks use the
contextual kind operations; the remaining backend-era legacy predicate occurs
only in the legacy-function fallback. No runtime conversion change is required
for this application-kind correction. The selected consumer audit is in
`/tmp/links-d7d3c-linearity-consumers.md`. Effect
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

The consistency layer first refines required guarantees with
`FrescoContext.require`, then uses strict assignment. Added requirements are
stored separately from declared kinds. A solved row retains its solution while
its flexible field and tail dependencies acquire the required guarantees.
Failure returns no updated context.

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

### Skeleton solution expansion and scope exit

`FrescoSkeletonOps.expand_solutions` and `leave_scope` preserve both ghost
forms and use the persistent context for solution lookup and scope checks.
Stored solutions start in their own lexical scope. Output binders can close
resulting rigid variables only when their full metadata agrees. Raw declaration
records remain unchanged, so their captured solved variables remain live.
Copies preserve recursive points and shared roots in matching lexical scopes.

Reuse context scope checking through a projection of
variable occurrences and binders. Include vacuous binders and put raw captures
behind fresh private nominal declarations. This retains independent raw scope
and captured solution IDs. A separate skeleton scope checker would repeat
context ordering and liveness rules. The projection establishes scope and
variable metadata; inference must check requirements through ghost-bearing
constructors.

Before combining shared solution and ambient graphs, compare every independently
supplied declaration snapshot with the same identity. Include nested declarations,
formal metadata and linearity. Deduplicating first can replace a live declaration
body with a different dead solution's body and introduce an escaping rigid
variable. Compare converted declarations with existing skeleton records before
reusing those records. These checks leave input graphs and contexts unchanged.
Shared callbacks must form a finite, stable graph of callback identities;
they may allocate fresh body syntax. Existing declaration maps and detached
snapshots satisfy this contract.

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

Keep an explicit set of added guarantees on each flexible
context entry and exported variable. Preserve `Unl`, `Base`, `Mono`, `Session`
and absolute-payload requirements as conjunctions. `Base` entails the ordinary
`Mono` predicate; `Session` permits polymorphic message payloads and does not
entail `Mono`. Empty rows and absent fields can meet both `Base` and `Session`;
a value type cannot. A fresh stronger representative was the main alternative,
but the existing ordinary kind descriptor cannot express every conjunction.

Reuse the finite Boolean summary checks to find flexible
dependencies. First test whether giving every eligible unknown the requested
guarantee would suffice. Then remove each candidate guarantee in turn to find
which unknowns need it. These summaries use conjunctions and fixed constructor
checks. Recheck the resulting set before returning it. A symbolic dependency
summary could avoid the extra evaluations but would add another summary domain.
Unused actual arguments do not acquire result requirements; their declared
parameter requirements still apply.

`FrescoContext.require` accepts a target's added requirements as well as its
declared parameter descriptor. Consistency can refine a candidate unknown before
strict assignment, including absolute-payload requirements on rows and presences.
`of_exported_variables` reconstructs a persistent context from the detached table.
It preserves order, freedom and every requirement, and rejects duplicate IDs,
invalid declarations, missing value-unknown monotype flags and invalid rigid
metadata. Detached export uses the same validation internally.

Keep semantic ordinary `Mono` separate from the syntactic monotype flag used
for assignment. An alias with an unused polymorphic argument can satisfy the
ordinary `Mono` predicate through its body. A variable declared `Mono`, or a
value-type unknown, retains the existing syntactic assignment check. Inferred
ordinary requirements must not make refinement order affect that distinction.

Queued requirements carry their lexical bindings separately from the context
callbacks. Following a stored solution or raw declaration resets the lexical
scope; explicit recursive binders retain their captured scope. Otherwise a
use-site binder with the same ID could supply a false guarantee. When expanding
a solution under an output binder, reject capture of an unresolved free flexible
variable. Preserve direct lexical shadowing and matching rigid closure.

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

## Signatures with independent effect variables

Track the general signature separately from each concrete use during migration.
Absolute modalities name fixed contexts; relative modalities add or remove named
effects from the ambient context. Neither binds a new effect variable. Ordinary
type variables may carry whole modal types but cannot occur as effect-row tails.

### Two independently handled thunks

`tests/effect_sugar.tests`, "Printer: presence_omit [3]: multiple shared effect
rows", takes thunks `p` and `q`, handles `E` in `p` and `F` in `q`, then returns
the two resulting thunks. Its printed legacy type is:

```links
(() {E:() => ()|a}~> (), () {F:() => ()|b}~> ())
  -> (() ~a~> (), () ~b~> ())
```

The caller can choose unrelated residual rows `a` and `b` at the same construction
call. Each returned thunk retains its matching row. A direct signature preserving
this interface and both arbitrary row choices requires effect variables. Sharing
one ambient context would relate them; fixed absolute modalities would specialise
them. Record the general contract as deferred. The term and particular uses may
still migrate with fixed contexts or a changed interface.

### Callback interfaces requiring a migration audit

| Source | Independent effects | Migration action |
|---|---|---|
| `examples/extensible-case.links`, curried case helpers | Callback and returned-call effects are independent of construction | Use shared ambient contexts; retain the general contracts as deferred |
| `lib/stdlib/binaryTree.links`, `leftmost_child` | Unused comparator and caller have independent rows | Specialise to a shared ambient context; preserve the general contract as deferred |
| `examples/handlers/alert.links`, JavaScript `wait` declaration | Callback uses `e1`; scheduling call uses `e2` | Preserve the general contract as deferred; inspect actual callback effects before specialising |
| `lib/stdlib/mvu.links`, `runHandle` and wrappers | View/update/subscription callbacks share `e`; caller uses separate `f` | Audit call sites against the fixed spawned-body context and actor migration |
| `prelude.links`, `curry`, `flip`, `uncurry`, `compose`, `lf`, `-<-`, `->-`; `tests/freezeml/a9.links` | Callbacks and returned applications share a row independent of closure construction | Migrated helpers use a shared ambient context; assess remaining helpers separately and retain the general contracts as deferred |

The prelude's `Comp(a,e::Eff)` and `gen0`/`gen1`/`gen2` also expose effect-row
parameters. Their general interfaces remain deferred with explicit effect
variables. Concrete pure computations can use absolute modal types without
preserving those general interfaces.

The `wait` signature is:

```links
forall e1::Row, e2::Row. (Int, () ~e1~> ()) ~e2~> ()
```

Its JavaScript body in `examples/handlers/js/alert.js` schedules the callback with
`setTimeout`. A concrete callback using only `Wild` may admit an absolute type;
this does not preserve quantification over both original rows. MVU uses
`spawnClient`, so its concrete migration also depends on the selected actor rules.
Keep such specialisations visible and retain the original general cases for a
future explicit-effect-variable extension.

Several variables in a printed type do not alone establish a missing feature.
The pure bodies of `choose` in `tests/polymorphism.tests` and the fresh collector-
arrow tests in `tests/effect_sugar.tests` can use ambient arrows. Actor `Send` is already
covered by the change from effect-indexed processes to `Process(a)`.

References: thesis chapter 3 (`chapters/overview.tex`, "Effect polymorphism")
and `chapters/metx/encoding-rows-no-effvar.tex` describe the distinction between
fixed/relative contexts and explicit effect abstraction. The latter translation
covers the lexically closest effect-variable fragment and uses term-level masks.
It does not establish migration of every legacy Links signature into the current
mask-free subset. Update this record with accepted/rejected migration cases as
the source checker becomes available.

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
