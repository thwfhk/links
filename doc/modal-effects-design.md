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

Declarations bind effect identities and their operation signatures.
Reject duplicate operation names in a declaration and ambiguous
unqualified uses. Preserve declaration identities through module
desugaring. Handler annotations select one effect group and its type
arguments. Without an annotation, infer that group from the operation
clauses. Reject mixed groups in one handler; nesting handles several
groups. Return-only identity handlers remain valid Links programs and
introduce no effect group.

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
substantial changes before dependent work. D1 is the first task and
does not change parser or inference behaviour.

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

Keep tests for these corrections alongside the adapted reference tests.

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
