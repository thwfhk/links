# SmallLinks modal effect types plan

The language design and scope are in [SPEC.md](SPEC.md#scope).
This plan records milestones, dependencies, progress and checks.
[IMPL.md](IMPL.md) records significant implementation decisions.
[GUIDE.md](GUIDE.md) documents the language for programmers.
The [example status](examples.md) records source coverage and checks.

Work stays on `small-met`. See [Status](#status) for the completion
record and deferred work.

## Chat ownership

| Codex chat | Work | Chat ID |
| --- | --- | --- |
| Design modal effect types | Language design, specification, milestone planning and coordination across the MET chats. | `01a1d798-8605-7320-8010-0bbcb5bf437c` |
| MET 1–2: Baseline and syntax | Baseline checks, surface syntax, scoped effect contexts and modalities, declarations and type printing. | `01a1d82f-b4e7-7db0-b206-2ecb7a08a9af` |
| MET 3: Fresco inference | Bidirectional typing, monotype unification, modal checking and locks, instantiation, generalisation and data typing. | `01a1d82f-c3c3-74b2-a115-6b3e9dac451f` |
| MET 4: Handlers and native effects | Operation lookup and typing, interface arguments, handler clauses and resumptions, and native effect permissions. | `01a1d82f-ce00-7932-945c-4682691e466e` |
| MET 5–6: Integration and verification | Typed frontend and IR integration, migration of primitives, the prelude, the standard library, existing examples and tests, and combined build, test and installation checks. | `01a1d82f-dbeb-7a11-b1e8-2da85c3b7f2f` |
| MET guide and examples | Programmer guide, thesis and Fresco example ports, example registration and checks, and the example inventory and defect reports. | `01a1dd80-8244-7300-bb43-c9d254e2b891` |

## Tracking

Refine the lists as implementation proceeds. Each numbered item is one
commit with its related source, tests and documentation. Split an item
before starting it if it needs several commits. Keep each commit
buildable. Tick an implementation item only when its checks pass and
record its commit ID after committing.

Follow the [implementation approach](IMPL.md#implementation-approach)
when choosing what to reuse or restructure.

## Milestone tracking

A milestone is complete when every item and its completion check pass.
The design review in 1.2 is required before any compiler change. During
development, new representation and checker code may be introduced
before the active compiler switches to it. The completed compiler has
one modal effect system; remove the old effect inference path once the
migration is complete.

At each pause record the milestone, next action, blockers and latest
checks under [Status](#status). Include command, source revision, result,
log path and relevant failure excerpts. Record each deferred test or
example by name and reason. Move resolved design questions into
decisions in the spec. Keep implementation decisions in IMPL.md.

## Milestones

### 1. Review the design and record the baseline

- [x] **1.1** (`3552e33f`) Read the repository guide, thesis and
  Fresco sources. Draft the syntax, typing and inference contract,
  examples, review choices, milestones and implementation framework.
- [x] **1.2** (`21348680`) Record the approved design decisions in SPEC.md and
  update the affected checks.
- [x] **1.3** (`a69e93ba`) Build and record the starting compiler, native entry points,
  regression suites and IR unit tests. Inventory effect-bearing types
  in primitives, both preludes, standard library modules and examples.
  Classify each affected fixture as a modal translation, a changed
  acceptance expectation, or a dependency on a postponed feature, using
  the criteria in [SPEC.md](SPEC.md#migration-and-deferred-coverage).
- [x] **1.4** (`1d94cb21`) Add missing baseline tests for retained runtime behaviour:
  clause contexts, forwarding, shallow and parameterised resumptions,
  and value-linearity use. Separate future modal typing assertions from
  runtime assertions executable by the baseline.

Completion check: the design is approved, the baseline is reproducible,
and the required migrations and deferred features have named entries.

### 2. Update syntax and represent modal types

Depends on milestone 1.

- [x] **2.1** (`2a911a4e`) Introduce `List A` and `(| |)` variant type syntax.
  Update parsers, printers, primitive signature strings,
  preludes, libraries, examples and fixtures together. Preserve term
  syntax and data-row behaviour. Check nested lists, function elements,
  open and closed variants, open record rows and print-and-reparse
  behaviour. Reserve `List`, rename existing aliases that use that name
  and preserve their tests. Reject user declarations of `List`.
- [x] **2.2** (`bcf3816c`) Exclude `escape` from the first modal version with a clear
  diagnostic. Record dependent tests and examples as deferred. Keep the
  shared continuation machinery required by effect handlers.
- [x] **2.3** (`eba6c051`) Add a separate scoped effect-context representation,
  using interface identities and type arguments. Keep data-row
  unification intact. Check repeated interface instances with equal and
  different arguments, prefix subeffecting and instance order.
- [x] **2.4** (`eba6c051`) Implement modality action, composition, equivalence,
  transformations and residuals. Cover repeated masks, absent interfaces,
  interface-argument replacement, and transformations that fail despite
  equal actions at one ambient context.
- [x] **2.5** (`9de77c76`) Add effect-interface declarations and the reviewed modal
  syntax. Register member signatures and resolve operation references
  through their declarations and modules. Update source types,
  traversals, substitution, free-variable collection, kinds and both
  type printers. Cover interface arguments, modal prefixes, quantifiers
  and their combinations with list and variant types.
- [x] **2.6** (`a566ff95`) Enforce the reviewed surface syntax. Restrict `=>` to
  interface member signatures and parenthesised handler clause
  annotations. Reject nested list and modal element types without
  parentheses, and migrate any affected source or printer output. Test
  both unary arrow forms, `List A` and `List(A)`, the reserved `effect`
  keyword and the rejection of empty interfaces.
- [x] **2.7** (`9b9a1e10`) Check that sequential interface declarations and repeated
  imports follow the same scope as `typename`. Preserve the identities
  of earlier references and the existing rule against duplicate operation
  names. Test shadowing and reopening modules and repeated imports in one
  input and across REPL inputs. Make type printers choose a name that
  resolves to the right declaration when one is in scope. Mark
  interfaces with no visible name as out of scope and distinguish
  shadowed identities in diagnostics. Verify the resolved identities
  in print-and-reparse checks.
- [x] **2.8** (`66861cb0`) Fix [printing of shadowed type aliases](IMPL.md#28-shadowed-type-aliases).
  After an alias is shadowed, check an earlier value against the type
  printed by each printer when it can be written in source syntax.
  Cover plain aliases and modal aliases that refer to visible interfaces.
  Check the out-of-scope marker when expansion exposes a hidden interface
  or reaches the recursive alias expansion limit.

Completion check: the migrated list and variant syntax and the modal
type representation have focused checks. Record, variant and presence
behaviour remains covered, and `escape` is identified as deferred.
Reparsing types printed in source syntax preserves interface identities
in the current scope. Out-of-scope markers are diagnostic text.

### 3. Implement modal inference and polymorphism

Depends on milestone 2. Keep the running compiler buildable while the
new inference path is completed with its library dependencies.

- [x] **3.1** (`33b15eaa`) Introduce Fresco's bidirectional inference and checking,
  partial type information, consistency and instantiation. Reuse Links'
  unification for monotypes, data rows and presences where suitable.
  Make Fresco's control of polymorphic instantiation separate from
  monotype solving.
- [x] **3.2** (`33b15eaa`) Add ambient contexts, binding contexts, locks and
  first-class modal types to the Fresco checker. Cover functions, calls,
  annotations, modal introduction and variable access. Reuse the
  reviewed SmallLinks value-restriction check. Use the standard pure
  `intRange` helper for range syntax and test shadowing. Check absolute
  kinds independently of linearity.
- [x] **3.3** (`33b15eaa`) Integrate the retained explicit polymorphism forms,
  freezing, type abstraction and type application. Implement the
  reviewed generalisation rules for value, data-row and data-presence
  variables. Add rejection checks for missing modal information,
  ambiguous interface-argument/kind constraints and generalisation of
  shared interface arguments.
- [x] **3.4** (`33b15eaa`) Cover recursive and mutually recursive functions, local and
  global bindings, modules and imports. Update pattern typing and the
  rules for lists, tuples, records, variants and recursive types so that
  modal dependencies survive storage, projection and matching.
- [x] **3.5** (`141ef72d`) Fix recursive `Abs` checks so they follow the
  field types and respect enclosing modalities. Use the same field
  requirements when checking and narrowing kinds. Test absolute and
  ambient callback fields, including a recursive reference whose
  arguments change.
  Apply the [recursive type rule](SPEC.md#recursive-types). Accept a
  `mu` type under `[]` when its body reaches a variant. Keep the
  existing rejection of cycles through aliases, quantifiers and
  modalities alone.
- [x] **3.6** (`75356d76`, `2e77710f`) Reject types with a non-identity
  modality at `Base`. Test direct and indirect uses through aliases at
  `Base`, `Mono` and `MonoAbs`. Retain the existing checks on primitive
  types, row tails and field presences.
- [x] **3.7** (`4d94622c`) Require explicit universal binders in source signatures.
  Test type, row and presence variables, holes, leading modalities and
  lexical references through nested `forall`. Update the default and
  FreezeML preludes, standard library, active examples and fixtures in
  the same commit.
- [x] **3.8** (`77d1ffee`) Apply Maetel's variable access rule before
  instantiation. Use consecutive leading modalities for the residual.
  Test access at a still-bound quantifier, absolute access, and explicit
  type application on both sides of a lock. Make grouped frozen variables
  behave like `~x`.
- [x] **3.9** (`77d1ffee`) Use all available partial type information
  before fixing polymorphic or modal instantiation. Test argument order,
  curried applications and modal pattern binders. Keep modality conversion
  independent of constraint order and ask for an annotation when the
  available constraints leave a choice. Use known frozen argument
  types before checking conversions. Restore the FreezeML test for
  `map(head)(single(ids))` without explicit type arguments.
- [x] **3.10** (`3557f45d`, `d93cf72f`) Check the value restriction on
  every path that introduces a quantifier or modality. Cover effectful
  computations, failing binding patterns, and computations that return
  an already-polymorphic or modal value. Check that annotation variables
  cannot escape.
- [x] **3.11** (`2abeefb8`) Preserve known quantifiers during record
  projection and extension, and preserve expected element types in list
  comprehensions.
  Test extending a quantified record with a `Presence(Abs)` field
  after explicit instantiation.
  Require a discarded record tail in an upcast to be unrestricted.
  Require matching argument counts in function upcasts. Test an accepted
  upcast with matching counts and a rejection with different counts.
  Run strict lowering checks here and repeat them after integration in 5.7.
- [x] **3.12** (`d48a31fb`) Preserve a field with `Presence(Abs)` when extending a
  [closed modal record](SPEC.md#modal-record-extension). Cover a field
  that is absent or present, a presence without an `Abs` bound and a
  record whose type must be instantiated first. The general interaction
  with row and presence variables is
  [future work](SPEC.md#modal-types-and-data-rows).
- [x] **3.13** (`3a631692`) Use argument types and the value restriction
  before choosing a modal type argument. Accept `same(number(), (42 : <R> Int))`
  at `List Int` when `number()` has a fixed `Int` result. Keep the
  modal result when `number()` is replaced with `id(1)` and `id` can
  be instantiated at a modal type. Check both argument orders when
  a frozen record field determines a shared field type.
- [x] **3.14** (`fadf5af7`) Check an eligible conditional branch at the
  expected result type even when another branch is a computation. Turn the
  [signed recursive example](SPEC.md#binding-rules) into a regression
  and check that a call cannot introduce a fresh `forall`.
- [x] **3.15** (`b9b6e057`) Preserve the scope of an unconstrained monotype when
  rechecking an inferred callback with a quantified parameter. Check
  the `fromPair` and [Church fold](example-issues.md#frontend-rechecking-fails-for-a-callback-pair-with-an-unconstrained-result)
  examples with default settings, frontend rechecking, strict IR checking,
  and both checks enabled. Keep rejecting source abstractions with an
  unconstrained type variable introduced inside the abstraction.

Completion check: the inference examples in SPEC.md have the specified
types and annotation requirements. Tests cover both accepted and
rejected higher-rank, modal, data-row and linear cases.

### 4. Type operations, handlers and native effects

Depends on milestone 3.

- [x] **4.1** (`0a9eaaa9`) Implement lookup of an operation's owning interface and
  its newest instance. Infer shared interface arguments and instantiate
  per-operation quantifiers separately at each call. Check absolute
  payloads and results. Reject incomplete interface handlers.
- [x] **4.2** (`0a9eaaa9`) Implement deep handlers, input locks, modal return bindings,
  implicit returns, forwarding and multi-shot resumptions. Cover nested
  instances of one interface with different type arguments and
  enclosing-context operation and return clauses. Cover several
  complete interfaces in one handler, forwarding of other interfaces,
  explicit forwarding of members and handlers with only a return clause.
- [x] **4.3** (`0a9eaaa9`) Implement shallow and parameterised handler rules. Preserve
  state evaluation order, resumption argument order and existing value
  usage checks. Cover dependent return values inside records and lists.
- [x] **4.4** (`0a9eaaa9`) Implement the reviewed native permission rules. Test
  native calls under absolute annotations, recursion and ranges. Keep
  native primitive classification separate from `ApplyPure`.
- [x] **4.5** (`13b074fd`) Fix inference of shared interface arguments. Use known
  types from handled expressions and clauses to
  [choose the interface arguments](SPEC.md#shared-interface-type-arguments).
  Check that reordering equally valid constraints produces the same
  type or the same request for an annotation. Cover known types in
  branches, local value bindings and local function bodies.
- [x] **4.6** (`13b074fd`) Use return and operation clauses when inferring the
  handler's result. Retain known modal types from aborting clauses
  and pass expected type information through return bindings. Test
  default and explicit returns, including a return through a local
  binding, as well as handlers used as application arguments.
- [x] **4.7** (`13b074fd`) Check that member quantifiers cannot escape into an
  outer type or a shared source annotation. Allow a flexible type
  variable that is used only within one operation clause to be
  solved there. Test both uses of the same annotation syntax.
- [x] **4.8** (`13b074fd`) Apply the reviewed handler usage rules. Check a captured
  linear value in all shallow clauses as alternatives. Require each
  deep clause to use its [linear state](SPEC.md#linear-state) once on
  each branch. Test one, zero and two uses, including the implicit
  return, state binder shadowing and passing linear state to a
  resumption. Check replay through an enclosing handler and sequential
  state initialisation.
- [x] **4.9** (`13b074fd`) Use the same rule for relative prefixes on absolute
  results in `if`, `switch` and handlers. Test matching underlying
  types, conflicting underlying types and results that still depend
  on their context.
- [x] **4.10** (`15849dea`) Check the reviewed `wild` signatures for `show`,
  `parseDate` and `sleep`, the pure `error` signature and the existing
  `exit` signature.
- [x] **4.11** (`314136f3`) Give `case n -> n` and `case n -> (n : Int)` the same
  typing when `n : Int`. In a handler with an effectful input of type
  `Int`, both clauses should reject an expected result of `[] Int`.
  Keep an explicit modality on the clause result, as in `n : [] Int`.
- [x] **4.12** (`367b904e`) Propagate expected result types through `switch` returns
  that [forward the handler input](SPEC.md#forwarding-returns) in every
  branch. Test a return through a pattern alias and a shadowing binding
  that returns a different value.
- [x] **4.13** (`6c054ee5`) Report incompatible type requirements for a shared handler
  interface argument. Preserve the annotation diagnostic when the
  observed types leave a genuine choice or omit a possible modality.

The [deferred optimisation issues](IMPL.md#deferred-optimisation-issues)
cover eliminating unused primitive calls and inlining linear reads.
The native signature checks in 4.10 use the default execution path.

Completion check: every handler and native-effect example in SPEC.md has
the specified type and result or error. Native dispatch and resumption
results agree with retained baseline runtime assertions. Mask modalities
never change operation dispatch. The
[milestone 4 follow-up](IMPL.md#milestone-4-follow-up) checks pass.

### 5. Integrate the compiler and migrate the library

Depends on milestones 2–4. Prepare each runtime-library dependency before
switching the active inference path.

- [x] **5.1** (`fcb1e97a`) Update primitive and default-alias types, the default and
  FreezeML preludes, standard library modules and desugared helper calls.
  Translate same-context callbacks and update explicit type arguments.
  Resolve or record `Comp` and `gen0`–`gen2` dependencies.
- [x] **5.2** (`fcb1e97a`) Update typed frontend transformations, handler-pattern
  lowering, sugar-to-IR translation, IR type checking, substitutions and
  closure conversion. Preserve modality information until every check
  needing it has run. Keep the native runtime representation and the
  independent `ApplyPure` primitive classification. Preserve resolved
  interface and operation identities through compilation and dispatch.
- [x] **5.3** (`fcb1e97a`) Switch native file, expression and REPL entry points to the
  modal checker with the migrated runtime library. Remove the replaced
  effect-arrow syntax, `effectname`, effect-row inference and effect-only
  settings or coercions. Keep shared code required for data rows and
  polymorphism.
- [x] **5.4** (`fcb1e97a`) Migrate regression fixtures, examples and expected printed
  types. Keep original assertions where they still apply. Record each
  unavoidable deferral with its feature dependency; update example
  registration and aggregate runners together. Give the REPL handler
  fixture's `ask` its required signature while retaining its check
  across successive sentences.
- [x] **5.5** (`7f1f3f8c`) Keep resolved interface signatures available in local modules
  and carry interface and operation names with the exported values and
  types of a prelude or a non-isolated input. Check that dependency loading
  recognises local modules in the same scopes as ordinary declarations.
  Test local module handlers and their scope, a custom prelude,
  successive inputs with both isolation settings, and REPL imports
  and failed loads.
- [x] **5.7** (`7f1f3f8c`) Preserve the checked types during lowering of quantified
  record operations, comprehensions and upcasts. Run the regressions
  from 3.11 through ordinary execution, typed frontend rechecking and
  strict IR checking. Include a list with modal elements and the record
  extension after explicit instantiation. Check that strict IR checking
  accepts matching function arities and rejects a cast that changes
  the argument count.
- [x] **5.8** (`7f1f3f8c`) Support [linear lists](SPEC.md#list-linearity). Update list
  kinds, inference, pattern lowering and primitive types together.
  Check that cons and append preserve all the elements and that list
  patterns split each list once on a matching path. Keep the
  unrestricted bounds on consumers and comprehension helpers that
  depend on them. Test empty and non-empty lists, nested patterns and
  whole-list fallbacks. Reject duplication, discards and calls to `hd`
  or `tl` on a linear list, including with explicit type application.
  Run the accepted examples with typed frontend rechecking and strict
  IR checks.
- [x] **5.9** (`7f1f3f8c`) Apply [REPL recovery](SPEC.md#repl-recovery) after runtime
  errors and early `exit`. Check a linear move before an interruption
  and a move the interruption skips. Check that an interrupted module
  leaves no new names in scope and that an exit value is printed without
  the type of the skipped result.
- [x] **5.10** (`7f1f3f8c`) Keep the [pure state helpers](SPEC.md#prelude-and-example-behaviour)
  and remove the `Abs` requirement on the results produced by `fmap`
  and the elements produced by `sequence`. Test both with functions
  created during a state computation. Keep a rejection test for a
  non-absolute argument captured by `return`.
- [x] **5.11** (`7f1f3f8c`) Restore caller handling of `Fail` in the
  [SAT example](SPEC.md#prelude-and-example-behaviour). Test that
  `leftBiased` tries the second branch, that a caller can handle final
  failure from either helper, and that malformed input still gives
  `Nothing` from `parseTextExpression`.
- [x] **5.12** (`7f1f3f8c`, `4b63194d`) Lower list comprehensions to the
  [standard helpers](SPEC.md#prelude-and-example-behaviour). Test
  shadowing with one and several generators and with `orderby`.
  Check that `for` works with empty and custom preludes that define
  no list helpers and gives the same results as with the default
  prelude. Explicit calls still use the definitions in scope. Run
  the tests with typed frontend rechecking and strict IR checks.
- [x] **5.13** (`7f1f3f8c`) Check [custom comparisons](SPEC.md#comparison-operators)
  against their definitions in scope and require a `Bool` result.
  Lower each call to the same definition the checker used. Test an
  accepted custom comparison, a declaration returning `String`, a
  scoped redefinition and the built-in comparisons. Run with typed
  frontend rechecking and strict IR checks.
- [x] **5.14** (`85ad25b5`) Preserve quantified field types when lowering
  record and tuple patterns. Use the same type application and abstraction as
  field projection. Under strict IR checking, bind a polymorphic
  function with each pattern and use it at `Int` and `Bool`.
- [x] **5.15** (`5c48a1d7`) Preserve native evaluation order when the REPL tracks
  linear moves. Run the same failing expression before and after
  defining and consuming an unrelated linear value. Keep the checks for
  moves that run and moves that an interruption skips.
- [x] **5.16** (`e4f876ea`) Check captures in later comprehension generators. Reject
  captures of linear values where a generator can run several times or
  be skipped. Test ordinary source checking and frontend rechecking.
- [x] **5.17** (`31b37db3`) Resolve each comprehension generator source in the scope
  outside the comprehension. Test a later source that refers to an
  outer list shadowed by an earlier generator pattern. Preserve the
  number and order of evaluations of generator sources.
- [x] **5.18** (`1c74f64a`, `66ee9476`) Lower an alias of a negative variant pattern at the
  narrowed type. Run the `(-Tag as x)` regression with default and
  strict IR settings, including in the full strict handler suite.
- [x] **5.19** (`5e971724`) Follow up on
  [5.14](IMPL.md#514-quantified-record-and-tuple-patterns) for list and
  variant patterns nested in quantified records and tuples. Preserve
  their field types on success and when a failed match continues to a
  later case.
  Run the reported probes with default settings and strict checking.
- [x] **5.20** (`f9d190ef`) Follow up on
  [5.18](IMPL.md#518-negative-variant-aliases) for aliases that enclose
  a nested negative pattern. Preserve the
  narrowed type through records, tuples, lists and variants. Check
  successful matches, fallthrough and linear payloads under strict IR
  checking.
- [x] **5.21** (`baabdd76`) Restore
  [transitive import visibility](SPEC.md#module-imports).
  Test qualified terms, type aliases, interfaces and operations,
  repeated imports and shadowing across source scopes.
- [x] **5.22** (`553db80e`) Check
  [import initialisation order](SPEC.md#module-imports).
  Dependencies run before their importers. Independent imports follow
  written order and a shared dependency runs once.
- [x] **5.23** (`c2d62aeb`) Make SAT `leftBiased` pure to construct. Test construction
  in an empty effect context, invocation under a handler and rejection
  of invocation without `Failure`.
- [x] **5.24** (`8efa59ce`) Apply
  [exit recovery to file inputs](SPEC.md#exit-from-a-file).
  Check definition rollback, linear uses, later inputs, `@load` and
  the existing handling of ordinary runtime errors.

Keep the concrete [handler demos](SPEC.md#prelude-and-example-behaviour)
while the old APIs that let callers choose additional effects are
deferred. The [lambda evaluator](MIGRATION.md#installed-examples) stays
deferred for this version. The design records [modality-parameterised
handlers](SPEC.md#modality-parameterised-handlers) as future work.

Completion check: the default prelude loads; files with imports, `-e`,
REPL bindings and typecheck-only execution work. Typed frontend and IR
checks pass, and no active code relies on the old effect-row path.

### 6. Verify and document the modal language

Depends on milestone 5.

- [x] **6.1** (`fcb1e97a`) Independently review the combined compiler changes against
  SPEC.md and resolve findings. Check handler scopes, modal erasure,
  kind constraints and preservation of data rows and value linearity.
- [x] **6.2** (`fcb1e97a`) Update the SmallLinks guide to the approved syntax and
  inference rules. Turn every accepted and rejected design example into
  a registered regression and run all executable guide examples.
- [x] **6.3** (`fcb1e97a`) Run final build, regression, IR, source and installation
  checks on the combined revision. Record remaining deferred cases and
  their reasons. Complete this plan only when the in-scope checks pass.
- [x] **6.4** (`2135e426`) After the follow-up changes in 2–5, update the
  SmallLinks guide, including signatures, lock access, recursive
  types, linear lists, REPL recovery, comparisons and comprehension
  helpers. Cover [interface names and printing](SPEC.md#effect-interfaces),
  [handler usage](SPEC.md#shallow-and-parameterised-handlers),
  [upcasts](SPEC.md#upcasts-and-record-updates) and
  [modal record extension](SPEC.md#modal-record-extension).
  Review the combined changes and run the affected checks below.
  Record the new tested revision and log paths.
- [x] **6.5** (`66ee9476`) Review and verify the combined fixes in 5.14–5.18 with the
  default runtime path. Include the full strict handler suite. Record
  the tested revision and check logs.
- [x] **6.6** (`5e971724`) Review 5.19 independently and run the combined
  checks on the new revision.
- [x] **6.7** (`f9d190ef`) Review 5.20 independently and run the combined
  checks on the new revision.
- [x] **6.8** (`8efa59ce`) Review items 5.21–5.24 independently and run
  the combined checks on the new revision.
- [x] **6.9** Create the programmer-facing [language guide](GUIDE.md),
  update documentation links, and keep the latest check results in this
  plan. Check the guide's examples and local links.

Completion check: a clean CI build and temporary installation work,
all in-scope regressions and unit tests pass, the guide matches the
compiler, and deferred features have an explicit inventory. Types
printed in source syntax can be reused as annotations in the same
scope. An out-of-scope marker indicates diagnostic text. The printer
can emit one for an [interface with no usable name](SPEC.md#effect-interfaces)
or when [recursive alias expansion reaches its limit](IMPL.md#28-shadowed-type-aliases).

## Checks

Use the default execution path for follow-up checks. Checks specific to
`--optimise` are deferred.

1. Run `make` after compiler edits and before tests. Save full output to
   log files. Test `./links -e`, file execution with an import, a REPL
   definition and call, and `./links --set=typecheck_only=true file.links`.
2. Start handler and effect changes with
   `./test-harness tests/handlers.tests` and
   `./test-harness tests/effect_annotations.tests`. Run affected suites
   separately, preserving their applicable configuration.
3. For inference and representation changes include `polymorphism`,
   `freezeml`, `annotations`, `functions`, `mutual`, `records`, `variants`,
   `presence_type_arg`, `desugar_datatypes`, `type_print`,
   `roundtrippable_types` and `typecheck_examples`. Run the active
   interface declaration checks in `effectname`.
4. For integration include `recheck_frontend_transformations`, `typed_ir`,
   `native`, `collections`, `library` and `modules`. Cases requiring
   `escape` remain in the deferred inventory.
   Run `opam exec -- ./run-tests unit-tests` for affected IR code.
5. Add focused tests for the new modality algebra and every SPEC.md
   acceptance criterion. Include the type printed for inferred values,
   shared interface arguments, wrong operation arity, interface-instance order,
   accepted pure modal introduction, rejected effectful introduction,
   modal fields and mask-only transport.
   Check forwarding of other interfaces, explicit member forwarding,
   incomplete interface rejection and operation-pattern failure
   separately. A failed pattern in a handler owning that operation must
   retain its match error; it must not forward to an outer handler.
6. Before completion run `make all-ci`, `make tests`, the IR unit tests,
   `make rule-check` and `git diff --check`. Include the example
   registration, REPL and print-and-reparse scripts. Do not repeat a
   full suite in several worktrees for an unchanged revision.
7. Since startup types and runtime files change, install to a temporary
   prefix using [INSTALL.md](../../INSTALL.md) and run
   `./tests/check-install.sh "$prefix/bin/linx"` from the repository
   root. The script checks execution outside the checkout. Test installed
   modal handler, import and polymorphism examples as well.

## Status

All MET milestones and reviewed choices are complete on `small-met`.
The latest tested compiler is `b9b6e057`. See the
[milestone 3.15 checks](#milestone-315-checks).
The [language guide and documentation checks](#documentation-checks)
passed for 6.9.
The example review can retest `fromPair` and the blocked Church example
on `b9b6e057`.

[Deferred language work](SPEC.md#future-work) includes effect variables,
term-level masks, lock access across quantifiers and `escape`. It also
includes [anonymous type holes](SPEC.md#anonymous-type-holes) and
[modality-parameterised handlers](SPEC.md#modality-parameterised-handlers).
See the [optimisation notes](IMPL.md#deferred-optimisation-issues)
and the [migration inventory](MIGRATION.md) for deferred fixes and examples.

### Milestone 3.15 checks

The baseline `81a07af4` rejected both callbacks during frontend
rechecking with `Type abstraction needs a type annotation`.
The checks for `b9b6e057` used OCaml 5.4.0. Logs are in
`/private/tmp/met-callback-pair.YNhYmY/`. Independent review checked
callbacks with aliases, nested quantifiers, and row and presence
variables. It also checked that using one result at `Int` and `Bool`
still fails and that source type abstractions still require all local
unknowns to be resolved. Review logs are in
`/private/tmp/met-callback-review.DNm6Lm/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` and `make all-ci` | Passed. | `candidate-build.log`, `ci-build.log` |
| `./links` on `fromPair` and `church-pair-result.links` | Each example produced the same type in all four modes. | `baseline.log`, `final-modes.log` |
| `./test-harness` on the affected suites | Passed, including frontend rechecking (6), polymorphism (70), FreezeML (67), typed IR (30) and example typechecking (94). | `<suite>.log` |
| `make tests` | 1,330 passed across 43 suites. Two existing cases were ignored. All six scripts passed. | `all-tests.log` |
| IR unit tests via `opam exec -- dune exec --profile=dev tests/unit/unit_tests.exe` with a separate build directory | All 105 passed. | `unit-tests.log` |
| `make rule-check`, `git diff --check`, document links and the `rg` tab scan | Passed. The tab scan covered the rule skipped without GNU find. | `rule-check.log`, `diff-check.log`, `documents.log`, `tabs.log` |

### Milestone 6.8 checks

The combined checks used `8efa59ce` with OCaml 5.4.0. Logs are
in `/private/tmp/smalllinks-met-6-8/`. Independent review checked import
scope and repeated declarations, pure SAT construction and caller
failure handling, and file exit rollback and isolation.

| Command or check | Result | Log |
| --- | --- | --- |
| `make all-ci`, including a fresh Dune build directory | Passed with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`. | `final-ci-build.log`, `final-clean-ci-build.log` |
| `make tests` | 1,236 passed across 42 suites. Two existing cases were ignored. All six scripts passed. | `all-tests.log` |
| `./test-harness tests/<suite>.tests` on affected suites | All passed, including modules (67), handlers (154), effect annotations (76), native permissions (13), example typechecking (34) and typed IR (30). | `default-<suite>.log` |
| Frontend rechecking and strict IR checks with the default prelude | Passed for handlers (154), effect annotations (76), collections (70), modules (67), records (51) and patterns (54). Both REPL scripts, the import order and file exit scripts, and the handler example runner passed under strict checking. | `strict-<suite>.log`, `strict-repl.log`, `strict-repl_effect_interfaces.log`, `strict-import_order.log`, `strict-file_exit.log`, `strict-examples.log` |
| `opam exec -- ./run-tests unit-tests` | All 105 passed. | `unit-tests.log` |
| Guide and temporary installation | All 18 runnable guide blocks and four entry points passed. `dune install` from the fresh CI build and `./tests/check-install.sh` passed. Installed probes covered transitive imports, order, SAT construction and file exit. | `guide.log`, `install.log`, `install-check.log`, `installed-follow-up.log` |
| `make rule-check`, `git diff --check`, tabs and document links | Passed. An `rg` scan covered the tabs rule because GNU find was unavailable. | `rule-check.log`, `diff-check.log`, `tabs.log`, `documents.log` |

### Documentation checks

The guide and navigation update used compiler source revision
`7b764a87` with documentation edits. No compiler or prelude files changed.

| Command or check | Result | Log |
| --- | --- | --- |
| `python3 /private/tmp/smalllinks-met-guide.dOGSYd/check_guide.py` using `./links` | All 28 fenced blocks checked: 25 programs returned the documented values, two produced the expected type errors, and one supplied the import fixture. All 16 additional syntax, file and REPL checks passed. | `/private/tmp/smalllinks-met-guide.dOGSYd/summary.log` and per-example logs in that directory |
| `python3 /private/tmp/smalllinks-met-guide-docs/check_docs.py` | Local links, headings, fences, tables and whitespace passed across the MET documents and documentation entry points. | `/private/tmp/smalllinks-met-guide-docs/documents.log` |
| `make rule-check` and `git diff --check` | Passed. | `/private/tmp/smalllinks-met-guide-docs/rule-check.log`, `diff-check.log` |
