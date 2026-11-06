# Modal effects design

## Status and scope

Implement modal effect syntax with scoped effect rows and refactor
Links' type inference to follow Fresco. Presence types remain in
record and variant rows. Scoped effect rows contain named effects
grouping operations. Existing effect annotations will be replaced
and affected programs migrated. Start with Met and implicit ambient
effects; explicit effect variables from Met(X) are deferred. Track
implementation tasks, progress, and verification in [PLAN.md](../PLAN.md).
Follow [AGENTS.md](../AGENTS.md) for repository conventions.

Database support, control-flow linearity, and session failure are out
of scope for now.
The term-level mask operator is deferred, including its syntax,
typing, runtime support, and tests. Scoped row removal and relative
modality composition remain in scope.

## Sources to examine

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

## Design procedure

Follow Aghilas' combined implementation for unresolved language
choices, as requested by the user. Record differences needed to
correct implementation defects or integrate Links constructs.
The sections below fix the initial design and implementation order.

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
  preserve repeated labels. The implementation also distinguishes
  effects using `eff_ho`; compare this behaviour with the chosen
  scoped row rules before adapting it.
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

## Types, syntax, and typing rules

### Surface syntax

Use `modal [E] A`, `modal <D> A`, and `modal <L | D> A`. The `modal`
prefix distinguishes modalities from list types and XML. A modality
binds to a primary type; parenthesise function and quantified types.
Effect applications use parentheses, for example `State(Int)`.
Ordinary arrows `(A) -> B` are interpreted in the ambient context.

```links
effect State(a::Abs) { Get : () => a; Put : (a) => (); }
sig read : modal [State(Int)] (() -> Int)
fun read() { do Get }
handle [State(Int)] (read()) {
  case x -> x
  case <Get => k> -> k(42)
  case <Put(x) => k> -> k(())
}
```

Use `effect higher E(...) { ... }` for Aghilas' higher-order `eff#`
declarations. The reference `#` spelling conflicts with Links comments.
Type parameters have modal kinds `Abs` or `Any`, alongside existing
record/variant row kinds. Unannotated type parameters default to `Any`;
ordinary operation signatures require absolute types, so an ordinary
effect parameter used directly as an argument/result must be `Abs`.

Add `freeze(e)` for general freezing and retain `~x` as an abbreviation.
Freezing is supported in checking positions, as in the reference.
The lexer enters a delimiter mode after `modal`, so angle brackets
there do not enter XML mode. `[A]` remains a list type. The reference
`{| e |}` freezing syntax already means page placement in Links.
Validate the grammar with Menhir during implementation.

During migration, distinguish implicit arrows in the surface syntax
from explicitly annotated legacy arrows. The legacy frontend converts
implicit arrows to its existing function nodes and anonymous effect
rows before type-variable and effect desugaring. The Fresco frontend
elaborates implicit arrows to contextual arrows. Apply the same
temporary legacy conversion in the built-in type-string reader;
its current initialisation path uses the ordinary parser. Remove the
legacy conversion and reader routing in D7. This keeps one grammar
and preserves the parsed distinction until inference selects the
appropriate representation.

D3b first adds modal type/binder syntax and implicit arrow nodes.
Store qualified effect names and positioned datatype arguments in
surface effect applications; declaration resolution later supplies
effect identities and higher-order flags. Modal types are primary
types, permitting nesting while requiring parentheses around arrows
and quantified payloads. Preserve modal binder metadata through
unresolved/resolved quantifiers and all syntax traversals. Modal kind
annotations apply to binders; existing kind annotations on variable
occurrences retain their ordinary meaning. The temporary legacy
normaliser rejects modal constructs explicitly. Subsequent D3 changes
add named effect declarations, handler annotations, freezing, and
contextual datatype elaboration with D4's kind checks.

`::Any` already denotes the Links kind `Type(Any,Any)`. Preserve that
interpretation and record modal kind `Any`; `::Abs` adds modal kind
`Abs`. Permit a modal annotation alongside an ordinary kind annotation,
matching the combined printer output, and reject repeated or
conflicting annotations. Modal angle delimiters must also be separate
from the lexer's effect-pattern chevron counter, which is activated
by `case`. Include both interactions in D3 parser tests.

Declarations bind effect identities and their operation signatures.
Reject duplicate operation names in a declaration and ambiguous
unqualified uses. Preserve declaration identities through module
desugaring. Qualify operations by their owning effect: `State.Get`
and `M.State.Get`, as confirmed by the user. Keep effect and operation
names separate from type, term, and variant-constructor names.
Handler annotations select one effect group and its type
arguments. Without an annotation, infer that group from the operation
clauses. Reject mixed groups in one handler; nesting handles several
groups. Return-only identity handlers remain valid Links programs and
introduce no effect group.

An annotated handler resolves unqualified operation clauses against
its selected effect, as confirmed by the user. Thus `handle [State]`
selects `State.Get` for a `Get` clause even when another visible effect
also declares `Get`. Qualified clauses still undergo owner checks.

Split the remaining declaration work into syntax with legacy rejection,
then effect and operation resolution. Allocate stable identities before
checking declaration bodies, permitting signatures to mention their
own effect. Preserve declaration parameters, operation signatures, and
handler annotations until contextual elaboration can check their kinds.
Module scopes must retain all candidates for an unqualified operation;
opening the same declaration twice does not create an ambiguity.
Use the same resolved operation identity in invocations and patterns.

Use separate effect lexical frames and module exports. An unqualified
operation uses the nearest frame containing candidates for that name;
one identity succeeds and several are ambiguous. Declarations and opened
module exports contribute candidates within a frame. Repeated opens
deduplicate identities. Inner frames hide outer operation candidates;
distinct effects within one frame remain ambiguous. Effect short names
introduced by opens follow Links' existing module/type name shadowing.
Qualified `E.Op` resolves E first, then Op in E's declaration.

Provide contextual resolution with explicit input/output state containing
scopes, headers, loaded modules, and identity allocation. Failed resolution
must leave the input state unchanged, and repeated interactive imports
reuse existing identities. Keep legacy operation handling unchanged in
the legacy module wrapper. The future Fresco frontend commits resolution
and typing states together after successful checking.

Header metadata used during resolution needs identities, source names,
positions, parameter and operation arities, ownership, and higher-order
flags. Preserve full parameter binders and signature syntax in declaration
nodes. Ordinary parameter subkinds can be inferred during type-variable
resolution; do not freeze guessed subkinds in an earlier header table.
Named effect parameters have primary kind `Type`. Header-first registration
permits self references; other declarations remain sequentially scoped.

### Scoped rows and modalities

An effect row is a finite list of named effect applications. Each
entry contains the effect identity, ordered type arguments, and the
ordinary/higher-order flag. There are no presence specifications or
effect row variables. Repeated entries are significant.

For ordinary effects, distinct labels commute and repeated labels
retain their occurrence order. Lookup and removal match the first
occurrence. Each removal label consumes one occurrence. Extension
prepends entries to the ambient row.

Include Aghilas' higher-order effect extension. Ordinary operations
require absolute argument and result types. Higher-order operations
permit arbitrary types, and invocation requires their effect at the
head of the ambient row. Equality permits exchange only between
distinct ordinary labels. Subeffecting permits moving an ordinary
label to the right across a distinct higher-order label. Keep equality
and subeffecting separate. Equality matches ordinary entries within
the current ordinary segment and higher-order entries at its boundary;
it must succeed in both directions. For subeffecting, an empty source
matches any remaining target, an ordinary source entry matches its
first target occurrence, and a higher-order source entry must match
the current target head. Thus `[] <= [H]` and `[H] <= [H,A]` hold,
while `[H] <= [A,H]` fails. Sources are `effects.ml:find_label_eff`,
`type.ml:sub_eff`, and the exchange tests. The thesis' disabled
higher-order section in `met/extensions.tex` gives background rules.

`[D]` maps any ambient row to `D`. `<L | D>` removes `L` from the
ambient row and prepends `D`. `<D>` abbreviates `< | D>`; the empty
relative modality is the identity. `compose m n` applies `m` first,
then `n`, following `effects.ml:compose`. Implement cancellation and
right residuals with label multiplicities. These type-level operations
remain required while the term-level mask operator is deferred.
Relative modality equality compares removal masks as multisets,
following `effects.ml:eq_mask`, and extensions with scoped row equality.
Traversal and printing preserve the supplied mask and row order.

For relative lock `m = <L1 | D1>`, guard `n = <L2 | D2>`, and ambient
row `F`, compute `G = remove L2 F` and `K = L1 - L2`. Take the shortest
prefix `P` of `G` containing all occurrences requested by `K`. Let `Q`
be that prefix after removing `K`. Return
`<labels(D1) ++ (L2 - L1) ++ labels(Q) | D2 ++ P>`.
When `K` is empty, both prefixes are empty. Fail if `G` lacks a
requested occurrence. Absolute cases follow the reference.

This corrects two defects in the reference residual: extraction must
skip occurrences already removed by the guard, and restoration must
preserve the position of higher-order entries. A successful result
`r` satisfies `apply r (apply m F) = apply n F` in literal row order.
The normalised removal masks of `compose m r` and `n` also agree.
The construction supplies a sufficient crossing modality. Failure
means this construction has no result. The reference's transformation
relation does not in general admit a principal residual for arbitrary
removal masks: at empty `F`, lock and guard `<A>` admit both identity
and `<A,A | A>` as incomparable remaining modalities. Keep this
limitation explicit when implementing variable access.

Use a polymorphic row module whose argument payload can contain Links
types or Fresco skeletons. Keep structural row operations pure. Obtain
the matching argument pairs before solving their constraints; failed
alternatives must not leave partially solved unknown type variables.

### Contexts, operations, and handlers

Typing carries an ambient row and an ordered context containing term
bindings, rigid type variables, unknown type variables, markers, and
modality locks. Variable access crosses the locks between its binding
and use, following `context.ml:locks` and `across`. Absolute values
cross context changes; other values require the modality access check.
Subtyping cannot bypass this check.

Invocation selects the first occurrence of the owning effect and
instantiates its operation signature with that occurrence's arguments.
A deep handler checks its computation in `D ++ E` under a `<D>` lock,
where `D` contains the handled group and `E` is the outer ambient row.
Return and operation clauses execute under `E`. Bind the return value
at `<D>A`. For ordinary operation `Ai => Bi`, bind its argument at
`Ai` and resumption at `Bi -> B`, where `B` is the handler result.
For higher-order effects, wrap each non-absolute operation argument
and result in `<D>` in the clause, following `type.ml:finfer`.

Require every operation of the handled group exactly once. Reject
missing, duplicate, and foreign clauses before checking the body.
Existing Links permits several argument-pattern clauses for one
operation. Migrate handler tests "Operation parameter pattern-matching"
(7)--(9) and the six affected handlers in `examples/handlers/nim.links`
to one clause containing a `switch`, preserving pattern order and
continuation calls. Add rejection tests for repeated operation clauses.
Preserve existing Links handler parameters and shallow handlers as
Links extensions. JavaScript currently rejects shallow handlers;
retain that diagnostic and verify deep handlers in both backends.
For an ordinary operation in a shallow handler, the resumption type
is `<D>(Bi -> A)`, where `A` is the handled computation's result,
following `met/extensions.tex`, rule `ShallowHandle`. Test both that
modality and the distinction between computation result `A` and
handler result `B` before integrating shallow handlers. Higher-order
shallow handlers require the corresponding modal argument checks
before they can be accepted.

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

Use Aghilas' fixed `Abs`/`Any` kind behaviour initially. The thesis
also describes refining unknown kinds from `Any` to `Abs`; that
behaviour is not present in the selected implementation. Record this
difference in acceptance tests.

Classify a quantified type under its declared binder kinds, following
`context.ml:get_kind`. Thus `forall a::Any. a` has kind `Any` and
`forall a::Abs. a` has kind `Abs`. The thesis' improved rule in
`met/extensions.tex` checks type binders at `Abs` when classifying the
whole quantified type, making the first example absolute too. Retain
the reference behaviour for this implementation and test the difference.

Local lets bind inferred types without generalisation. Explicit
polymorphic annotations and Fresco's quantifier introduction provide
polymorphism. Require signatures for recursive definitions; install
all signatures before checking a recursive group. Unsigned
non-recursive definitions retain their unknown type variables across
the top level. Migrate programs relying on implicit Hindley--Milner
generalisation or unsigned recursion by adding signatures. Global
signatures state absolute modalities explicitly, following Aghilas'
driver. Explicit type abstraction/application in Links remains
supported through separate Fresco checking rules; the reference parses
type application but lacks its inference case.

Retain record/variant row variables and presence types. Structural
consistency and subtyping use Fresco for field types and existing row
structure for labels and tails. Lists, tuples, aliases, and recursive
value types retain their representations; their payload types use
Fresco. Scope row unknowns with the same context ordering as type
unknowns and reject escaping rigid variables. Pattern bindings obtain
types from their scrutinee; branch results use Fresco's join. Modules
desugar before inference, preserving effect identities.

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
metadata must also retain modal kinds when D3 introduces declarations.
Contextual alias application and recursive unfolding must use structural
substitution and preserve quantified/modal bodies. The legacy alias
helpers also instantiate leading quantifiers and remain confined to
the legacy frontend during migration.

D3a implements `TypeParameter`, containing `Kind.t` and `ModalKind.t`, with
an `Any` default and `Abs` permitted only for primary kind `Type`.
Use it in abstract type arities, alias parameter descriptors, and
`rec_appl.r_quantifiers`. `Quantifier.to_parameter` copies both kinds
without allocating a variable identity. Structural consumers retain
the full descriptor. Legacy consumers use a checked projection to
`Kind.t` which rejects `Abs`. The legacy precheck must also inspect
unused declaration parameters on abstract, alias, and recursive
applications. A later D3 change adds contextual structural application
and validates argument modal kinds using the contextual kind checker.

The 18 D3a tests cover descriptor preservation, unused `Abs` parameters,
checked legacy projections, unchanged ordinary kinds/printing, and
rejection before mutation. Datatype desugaring projects every parameter
before desugaring any argument; this corrects the review finding where
a preceding recursive argument changed a point before a later `Abs`
parameter failed. All 152 unit tests and six selected regression suites
pass. Independent review confirmed the correction.

Split D2 into D2a, quantifier metadata and its preservation, and D2b,
contextual arrows/modal types and their traversals. D2a changes no
surface syntax. Test freshening, renaming, and rejection by legacy
inference explicitly before adding the new type constructors.

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

Migrate old `{Op:A|e}`, `Op{_}`, `-e->`, `~e~>`, `effectname`, and
effect-tail parameters. Built-in type strings are parsed during
initialisation, so migrate them before removing old parser productions.
Represent current `wild` as a named built-in effect for external
operations, and `hear` as a parameterised built-in receive effect.
Primitive operations can retain specialised runtime calls while their
signatures use named effects. Change `Process` to take its mailbox
message type, since its existing effect-row parameter includes an
effect tail that is outside the selected scope. A process identifier
does not need to expose all effects used by the process body.

The actor primitive `Send` (distinct from session primitive `send`)
and the core process signatures become:

```links
sig Send : forall a::Abs.
  modal [Wild] ((Process(a), a) -> ())
sig self : forall a::Abs.
  modal [Wild, Receive(a)] (() -> Process(a))
sig spawn : forall a::Abs, b.
  modal [Wild] ((modal [Wild, Receive(a)] (() -> b)) -> Process(a))
```

`Receive(a)` is the built-in mailbox effect. Spawned bodies use their
own absolute context because runtime handlers are not transferred
to a spawned process. Require absolute message types across processes;
effectful functions can be sent with an absolute modal type. Scope
the mailbox type unknown with the spawned body, and connect its
receive patterns to the resulting `Process(a)`. Test matching and
mismatching send/receive types, `self`, and captured effectful values
before migration. Preserve record/variant rows and session behaviour;
do not extend session failure or control-flow linearity. Record each
remaining primitive's effect requirements during migration.

### Dependencies and completion checks

| Change | Depends on | Completion check |
|---|---|---|
| D1: scoped rows and modalities | Design comparison | Duplicate/exchange/removal/composition/residual unit checks; compiler builds |
| D2: shared modal types | D1 | Traversals compile; substitution and printing tests |
| D3: declarations and syntax | D2 | Parsing/printing acceptance and rejection tests, including XML/list conflicts |
| D4: Fresco contexts and constraints | D2 | Scope, occurs, kinds, ghosts, consistency, and solving tests |
| D5: pure Fresco inference | D3, D4 | Adapted Fresco tests; annotations, applications, freezing, recursion elaborate |
| D6: modal inference and handlers | D1, D3, D5 | Operations run; modal access, repeated rows, complete groups checked |
| D7: Links constructs and migration | D5, D6 | All in-scope constructs and selected suites use Fresco/scoped effects |
| D8: backends and final review | D7 | Interpreter/JS deep-handler tests, docs, migration guide; no legacy effect inference |

Each change may need several buildable commits. Independently review
substantial changes before dependent work.

D1 is implemented in `core/effectRow.ml/.mli` and
`core/modality.ml/.mli`. `EffectRow.match_equal` and
`EffectRow.match_subeffect` return ordered argument pairs before any
payload comparison. `Modality.right_residual` uses the corrected
prefix construction. The 28 tests in
`tests/unit/ir/test_cases/modalEffects.ml` include duplicate and
higher-order acceptance/rejection cases and finite algebraic checks.
Independent code review reported no findings. Parser and inference
integration follows in D2b--D6; the old path is still present.

D2a is implemented. `Quantifier` stores variable identity, `Kind.t`,
and `ModalKind.t`; constructors default to `Any` and reject `Abs` on
row/presence binders. Copies retain both kinds. Structural substitution
preserves `Abs`; legacy inference and type application reject it.
Binder identity equality remains separate from full binder comparison.
Printers retain existing `Any` output and show `::Abs`.

The legacy guard checks recursive arguments and raw declaration bodies,
using `rec_appl.r_body` without unfolding or instantiation. It checks
each body once per call and every occurrence's arguments. An earlier
version unfolded recursive aliases before their declaration groups
were complete, causing internal errors. Only alias construction during
desugaring permits incomplete bodies; inference requires complete
declarations before mutation. Unit tests cover this boundary and
`tests/polymorphism.tests` contains the recursive-alias regression.
All 104 no-database unit tests and the four selected regression suites
pass. Independent review confirmed the fix and reported no further
findings.

D2b is implemented. Shared types contain contextual `Arrow` and
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
continuations. The 30 tests in `modalTypeTraversal.ml` cover these
checks, structural operations, recursive traversal, printers, and
legacy rejection. All 134 no-database unit tests and the four selected
regression suites pass; independent review reported no further findings.

D2b rejects recursive IR equality involving contextual arrows
or modal types explicitly. The existing IR checker accepts recursive
equality without comparing bodies; new modal types must not inherit
that shortcut. Recursive traversal and substitution remain required.
D8 must replace this temporary rejection with checked recursive
comparison before accepting recursive modal programs.

D3b adds the surface syntax for modal types, positioned effect
applications and masks, implicit arrows, and modal binder kinds.
All three sugar traversals visit their children and binder metadata,
including quantified types and value-binding quantifier lists.
Type-variable resolution preserves modal kinds and binder identities.
`Abs` fixes primary kind `Type`, including when ordinary kind inference
is enabled. The existing `::Any` annotation also records modal `Any`,
so `::Any::Abs` is rejected; an explicit ordinary kind such as
`::Type(Any,Any)` or `::(Any,Any)` can be followed by `::Abs`.

The modal lexer mode preserves variant/session delimiters and remains
separate from operation-pattern chevrons. Session payloads containing
qualified types retain the parenthesis requirement, for example
`?(modal [] M.T).End`. The grammar has no Menhir conflicts.
`DesugarLegacyTypes` runs after imported syntax has been loaded and
before module resolution through the legacy module-pass callbacks;
the direct module entry points preserve contextual syntax by default.
The built-in type reader also uses this temporary normaliser.
Modal type annotations and `Abs` binders receive positioned legacy
rejections. Effect declarations, resolution, and contextual elaboration
remain to be implemented.

D3c adds declaration, handler annotation, qualified operation, and
general freezing syntax. Operation references store a positioned effect
path and operation name. Declarations retain their parameter binders,
higher-order flag, and positioned operation arguments and results.
Handler annotations preserve existing depth and parameter fields.
Generic syntax traversals visit the new children; the standalone
type-variable pass preserves declarations until D3d supplies their
parameter scopes. The legacy normaliser and typed entry points reject
these constructs with source positions. The parser corrects the
constructor span queued by the existing effect-pattern lexer so a
qualified effect name excludes its opening `<`. Name resolution and
contextual typing remain to be implemented.

D3d implements effect and operation resolution through explicit
`DesugarModules.resolve_program` and `resolve_sentence` state.
`EffectHeaders` retains declaration identities, source positions,
ownership, arities, and higher-order flags. Local effect names leave
scope while their headers remain available. Imported module roots
are reused across interactive sentences. Resolution copies the mutable
module-name allocator before traversal, preserving input state on failure.

The resolver checks declaration duplicates, effect and operation arities,
and handler ownership, duplicate clauses, and completeness. Annotated
handlers resolve bare operation clauses against their selected effect.
Type-variable resolution gives each declaration fresh rigid parameter
binders, preserves modal kinds and inferred ordinary subkinds, and rejects
free named variables, including flexible variables. Anonymous row syntax
remains for contextual elaboration to check. Full signature typing and
modal-kind checks remain D4--D6 work. Legacy entry points retain their
existing operation handling and reject modal declarations before changing
their module state.

Split D4 into buildable changes. D4a adds non-mutating point reads,
raw recursive declaration binders, and modal kind classification.
D4b checks type well-formedness. D4c adds ordered contexts and checked
assignment; D4d adds scope exit and export before skeletons and constraints.

Add `Unionfind.peek` without changing `find`. Change `rec_appl.r_body`
to return the formal `Quantifier.t` list alongside the raw body;
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

`Unionfind.find` performs path compression. Add a non-compressing
descriptor reader for these checks; avoid mutable unfolding and
normalisation helpers. Exported types use fresh points.

Scope exit retains surviving flexible declarations and solutions,
removes local bindings and locks, and checks returned types and
retained solutions for escaping rigid variables. Follow
`lib/type.ml:protect_context`, which preserves flexible entries;
`lib/context.ml:protect_context` drops them. Export resolved types
using fresh, memoised points before later compiler passes can mutate
them. Keep row and presence unknowns in the same ordered context,
with structural solutions checked according to their primary kinds.

Subsequent D4 changes add recursive skeletons with `Ghost` and
`UniversalGhost`, including holes inside fields and effect arguments,
then consistency and constraint collection/solving. Conversion to
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
kinds. Unresolved row/presence variables prevent an enclosing record
or variant from being classified as absolute. Inspect known solutions.
Session input/output types combine payload and continuation kinds;
selection/choice types combine branch kinds. Ordinary linearity and
session restrictions remain separate checks.

Create fixed-point states on demand and revisit callers when results
or argument summaries change. An `Any` result remains `Any` if more
arguments become possibly contextual. Include captured parameter
summaries in recursive-binder states. Abstract constructors use explicit
rules keyed by identity: lists and map entries depend on their payloads,
access points on their protocols, and unknown abstract constructors
default to `Any`. Preserve the current process representation until D7.

D4a implements this classification in `frescoKind.ml/.mli`. Its callbacks
provide variable declarations and solutions, raw recursive declarations,
and abstract-constructor rules. Declaration states contain the declaration
identity and Boolean argument summaries. Recursive-binder states also
contain captured bindings; solution states use variable identities.
Re-evaluate demanded states when summaries change or new states appear.
Every result starts at `Abs` and can change once to `Any`. Recursive
references to a bound variable reuse its existing state.

`Unionfind.peek` reads descriptors without path compression. Raw recursive
bodies now retain their formal binders, and recursive declaration identities
separate names from group numbers. The tests include actual datatype
desugaring, both reference classification defects, argument changes, mutual
recursion, captured binders, and unchanged input graphs after classification.

For D4b, validate actual primary-kind structure, ordinary subkinds, and
modal kinds separately. Check each argument's tag against both its formal
parameter and its body. Check all application arguments even when the
result ignores them. Check session continuations and branches as sessions.
Existing `Types.Base`, `Unl`, `Session`, and `Mono` predicates use mutable
point reads or legacy unfolding; implement read-only checks with `peek`.
Do not copy the existing `Mono.type_satisfies` call that supplies `Session`
to its restriction predicate. An explicit ordinary `Mono` requirement is
separate from D4c's monotype obligations on value-unknown solutions.

For an explicit ordinary `Mono` parameter, a rigid variable declared
`Any` fails: substituting a polymorphic type for that variable would break
the parameter contract. A rigid variable declared `Mono` succeeds.
D4c's syntactic monotype check still accepts an older rigid `Any` variable
as an atom. If the unknown being assigned itself has ordinary restriction
`Mono`, its solution must also pass the stricter ordinary-kind check.
Keep these checks separate and do not narrow rigid declarations.

Use explicit ordinary-kind entailment in this checker. `Base` entails
`Mono`; `Session` does not, because session payloads may contain
polymorphic or modal types. The legacy `Restriction.min` relation accepts
the latter inclusion and cannot serve as an entailment test. Empty
`ForAll` binder lists are transparent for `Base` and `Mono`; D4c's
syntactic monotype traversal also treats `ForAll([], A)` as `A`.
Non-empty quantifier lists and modal types fail a `Mono` requirement.

At each recursive application, check its actual arguments. Validate each
raw declaration body under its own formal binders once per check, retaining
pending checks for mutually recursive bodies. Do not substitute arguments
or skip argument checks when a declaration is already active. Contextual
named type declarations return `Type`; reject legacy recursive effect
aliases. Preserve recursive type and row binders with their stated kinds.

Supply a separate effect-parameter callback to well-formedness checking;
keep D3d's headers unchanged. Check effect identities, arities, higher-order
flags, and ordinary/modal parameter kinds, including identities in masks.
Check ordinary operation arguments and results at `Abs`, and higher-order
signatures at `Any`, with a provisional self header in scope.

During contextual effect declaration elaboration, require closed operation
signatures with only explicit effect parameters and nested quantifiers.
Reject remaining anonymous type, row, and presence placeholders before
allocating unknowns. This follows the reference's explicit declaration
parameters and bound-variable lookup. D3d only preserves anonymous row
syntax for this later check. Expression annotation holes are a separate
part of contextual term elaboration.

D4b implements `FrescoKind.check`, `check_effect_row`, and
`check_effect_signature`. Structural validation queues kind requirements
after checking all children. Raw declaration bodies are checked once under
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

D4c uses persistent ordered contexts and a strict assignment operation.
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
source-program rejection. This keeps D4b's descriptor API unchanged.

D4c implements an abstract `FrescoContext`, with `FrescoTypeOps.assign`
delegating to its checked assignment operation. Context entries retain
declaration order, and lookup uses variable IDs. Type unknowns initially
require monotypes; row and presence unknowns acquire that requirement when
needed. Checks and dependency collection precede the returned context update.
Term and lock insertion also validate their types against the current context.

Recursive inspection tracks bound variables, active recursive binders,
nominal declarations and point paths separately. A repeated point under an
active recursive binder is valid. Entering a raw nominal body resets the
point path and uses the declaration guard. These rules accept shared
recursive graphs while rejecting unguarded point cycles. Keeping recursive
binders separate also prevents a quantifier with the same ID from hiding an
occurrence of the assignment target.

D4d scope exit takes explicit live type roots with their lexical binders,
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

Export several types together to fresh, memoised points. Return a declaration
table alongside the types for free rigid and unresolved flexible variables,
including ordinary kind, modal kind, freedom, and monotype requirements.
`Types.Var` alone cannot preserve `Abs` or structural monotype requirements.
Keep this table for later consumers; D8 must account for it before allowing
backend type operations. Read-only representative lookup is needed to retain
sharing between points in one Unionfind class without path compression.

Copy raw nominal declaration bodies and rebuild callbacks over the copied
graph. Snapshot declaration linearity. No exported callback may retain source
points or the inference context. The first D4d export may reject `r_unwind`
explicitly; D8 must supply capture-avoiding contextual unfolding before
recursive exported types reach consumers that unfold them. Preserve actual
cyclic point graphs with an explicit `Recursive` binder, while rejecting
cycles without such a binder.

## Examples and expected behaviour

These are target Links programs for the proposed syntax.

```links
effect Tick { Tick : () => Int; }
handle [Tick] (do Tick) {
  case x -> x
  case <Tick => k> -> k(42)
}
```

Expected type `Int`, result `42`. A nested inner Tick handler returning
`1`, followed by a Tick invocation under an outer handler returning
`10`, must produce `11`. Undeclared operations and invocation outside
an ambient Tick context fail.

```links
effect State(a::Abs) { Get : () => a; Put : (a) => (); }
sig same : modal [] ((modal [State(Int), State(Bool)] (() -> ())) ->
                     modal [State(Int), State(Bool)] (() -> ()))
fun same(f : modal [State(Int), State(Bool)] (() -> ())) { f }
```

This must typecheck. Swapping the State occurrences in the result
fails. Distinct ordinary effects A and B satisfy `[A,B] = [B,A]`.
For ordinary A and higher-order H, `[A,H]` is a subeffect of `[H,A]`;
equality and reverse subeffecting fail.

An identity annotated `forall a. modal [] ((a) -> a)` used at Int and
Bool typechecks. A local unannotated identity used at both types fails.
Adapt freezing acceptance and non-freezing rejection from
`tests/fresco/{pass,fail}/f2.mle`, modal access rejection from
`tests/fail/leak-effect-paper.mle`, and combined modal/polymorphic
acceptance from `tests/pass/fresco.mle`.

A State handler providing only Get fails even if its body uses only
Get. A return-only identity handler handles no group and is accepted.
Test duplicate/foreign clauses, incorrect operation arguments and
resumption arguments, and unknown effect applications.

### Reference verification and corrections

Built a copy of the reference in `/tmp` on 6 November 2026. Its suites
pass: 57 Fresco and 25 modal/data-type tests. Additional probes found:

1. Identical `[state int,state bool]{unit}` parameter annotations fail
   consistency. `join_sk_mod` and `solve_eq_mod` fold right-to-left
   while matching first occurrences. Use a shared left-to-right
   equality matcher in consistency and equality constraint
   collection/solving. The same defect affects
   `[ordinary,higher-order]`. Add reflexivity tests for both paths,
   and reject exchange across a higher-order entry in either direction.
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
   output contains the second. Restoring an ordinary A from ambient
   `[H,A]` also incorrectly produces `[A,H]` across higher-order H.
   Use the prefix construction above and test literal output equality
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
   aliases, so D4 must handle this case. Add kind-classification and
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

## Design decisions

- 6 November 2026: Use scoped rows for effects, with repeated labels
  and no presence types, as requested by the user. Preserve record
  and variant rows. Effect handling must therefore be separated from
  the shared row operations where their semantics differ.
- 6 November 2026: Refactor inference to Fresco, using the thesis and
  Aghilas' combined implementation as the main references. This
  requires both Fresco polymorphism and its modal inference extension.
- 6 November 2026: Replace old effect annotations and migrate affected
  programs, as confirmed by the user. Compatibility with the old
  effect annotation syntax is not a requirement.
- 6 November 2026: Implement Met with Fresco and implicit ambient
  effects first; defer explicit effect variables from Met(X), as
  confirmed by the user.
- 6 November 2026: Use named effects grouping operations as scoped
  row entries, as confirmed by the user. Follow the declaration
  structure in Aghilas' combined implementation when adapting the
  thesis' rules to Links.
- 6 November 2026: Defer the term-level mask operator, as requested
  by the user. Retain scoped row removal and relative modality
  composition for the modal type system.
- 6 November 2026: Select Aghilas' higher-order effects, fixed modal
  kinds, monomorphic let, and signed recursion defaults. Adapt surface
  delimiters to Links and correct the verified equality/context/handler
  defects described above. The main agent owns these decisions under
  the user's instruction to proceed with reference defaults.
- 6 November 2026: Represent `Process(a)` by mailbox message type,
  using absolute message types and a separate built-in `Receive(a)`
  effect. This removes process effect-tail parameters while preserving
  typed actor messaging. Shallow handlers follow the thesis rule.
