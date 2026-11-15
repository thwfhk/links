# SmallLinks modal effect types plan

The language design and scope are in [SPEC.md](SPEC.md#scope).
This plan records milestones, dependencies, progress and checks.
[IMPL.md](IMPL.md) records significant implementation decisions.
[GUIDE.md](GUIDE.md) documents the language for programmers.

Work stays on `small-met`. See [Status](#status) for the completion
record and deferred work.

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
The latest tested compiler is `8efa59ce`. See
[milestone 6.8 checks](#milestone-68-checks).
The [language guide and documentation checks](#documentation-checks)
passed for 6.9.

[Deferred language work](SPEC.md#future-work) includes effect variables,
term-level masks, lock access across quantifiers and `escape`. It also
includes [anonymous type holes](SPEC.md#anonymous-type-holes) and
[modality-parameterised handlers](SPEC.md#modality-parameterised-handlers).
See the [optimisation notes](IMPL.md#deferred-optimisation-issues)
and the [migration inventory](MIGRATION.md) for deferred fixes and examples.

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

## Example ports

The [example README](../../examples/met/README.md) gives run commands.
[EXAMPLE_ISSUES.md](EXAMPLE_ISSUES.md) records compiler issues and
inference limits.

### Sources

- Wenhao Tang's thesis at `eabef130ffb744840fe8a52e0cbb4045fe2cc397`.
  The tutorial is `chapters/overview.tex`.
- The Fresco artefact at `333738dbe9da1dcd094a6b2c2c9dbb9eec701ea4`.
  The source material is the README program, `tests/pass`, `tests/fail`
  and the appendix tests in `tests/fresco/pass` and `tests/fresco/fail`.

### Example source coverage

The inventory covers 42 thesis listings and 83 Fresco programs, test
files and README examples. Shared examples and related typing cases
use the same SmallLinks file.

#### Thesis tutorial

The source is `chapters/overview.tex` in `phd-thesis` at
`eabef130ffb744840fe8a52e0cbb4045fe2cc397`. The chapter has 42 listings
and includes no separate source files.

| Source lines | Example | Coverage |
| --- | --- | --- |
| 62–65, 69–72, 76–79, 84–88, 92–96, 116–125 | [pure.links](../../examples/met/thesis/pure.links) | `pi`, `inc`, `pinc`, `map` and curried `iter`. Both placements of `forall` around the outer `[]` are checked for `map` and `iter`. Returns `((), [4, 2, 5, 2, 6, 10], 42, 43)`. |
| 180–185 | [print_list.links](../../examples/met/thesis/print_list.links), [handlers.links](../../examples/met/thesis/handlers.links) | `IO`, `Gen`, `State` and `ND`. The `PolymorphicResult.ND` interface gives `Fail` the absolute polymorphic result `[] (forall a. a)`. The last result list is `[42]` after dropping the failing branch. |
| 231–240, 262–265 | [handlers.links](../../examples/met/thesis/handlers.links) | Bare arrows for the three local increment functions share the context containing `Gen(Int)`, `State(Int)` and `ND`. The local run returns `(6, 64, [4, 2, 5, 2, 6, 10])`, giving the final state, number of possible lists and yielded values. |
| 276–278 | [iter_pure_result.links](../../examples/met/thesis/rejected/iter_pure_result.links) | Rejects access to `f` under the empty context asserted by the returned function's `[]`. |
| 288–291 | [print_list_without_io.links](../../examples/met/thesis/rejected/print_list_without_io.links) | Rejects `do Print` because `IO` is absent from the current context. |
| 316–325, 385–390, 395–401, 406–412, 417–426 | [handlers.links](../../examples/met/thesis/handlers.links) | Increment functions with absolute contexts and three handlers with relative callbacks. `asList` returns `[4, 2, 5, 2, 6, 10]`. `all` produces 64 lists, from `[4, 2, 5, 2, 6, 10]` to `[3, 1, 4, 1, 5, 9]`. `state` returns `6`. |
| 349–352 | [print_list.links](../../examples/met/thesis/print_list.links) | `printlist` uses a callback and `Print` in `[IO]`. A mock `Read` supplies the heading, and the handler collects `["digit 3", "digit 1", "digit 4"]`. |
| 458–460 | [handlers.links](../../examples/met/thesis/handlers.links), [absolute_generator_callback.links](../../examples/met/thesis/rejected/absolute_generator_callback.links) | The absolute `asListAbsolute` callback yields `[42]`. The callback that also calls `Get` is rejected because its `[Gen(a)]` context excludes `State`. |
| 514–517, 526–529 | [handlers.links](../../examples/met/thesis/handlers.links) | The inner `state` handler forwards `Yield` to `asList`. Returns prefix sums `[3, 4, 8, 9, 14, 23]`. |
| 546–550, 555–558 | [handlers.links](../../examples/met/thesis/handlers.links) | The inner `state` handler forwards `Choose` to `all`. Returns 64 sums, starting with `[23, 14, 18]` and ending with `0`. |
| 588–594, 625–627 | [find_unannotated_callback.links](../../examples/met/thesis/rejected/find_unannotated_callback.links), [find.links](../../examples/met/thesis/find.links) | Rejects calling the bare predicate under a new `Gen` handler. The relative predicate `<Gen(a)> (a -> Bool)` supports that call. The successful search, failed search and predicate that yields return `(Just(6), Nothing, Just(12))`. |
| 649–655 | [find_mask_paper.links](../../examples/met/fresco-effects/find_mask_paper.links) | The term `mask<Gen>(p x)` needs term-level masks. The shared port handles `Test` and the local `Yield` together. Its `Test` clause calls the predicate in the enclosing context, so its yields reach the caller. The `observed` result is `(Just(2), [1, 2])`. |
| 687–690 | [yield_state.links](../../examples/met/thesis/yield_state.links) | The original `yieldState` API needs a term mask to call `<Gen \|>` under a caller-installed `Gen`. The runnable version handles a new `RunCallback` operation together with the inner `Gen(Int)`. The callback updates the current `State` and yields to the outer `Gen(String)`. The resumption yields the updated state to the inner handler. Returns `([42], ["callback"])`. |
| 721–723 | [processes.links](../../examples/met/thesis/processes.links) | A recursive variant `TutorialList` represents `Nil` and `Cons`. Summing the example list returns `42`. |
| 732–741, 753–756 | [processes.links](../../examples/met/thesis/processes.links) | A `Proc` constructor stores a callback with an ambient arrow. `push` appends a process while `next` passes the remaining queue. Running two copies of `[State(Int)] Proc` increments state from `40` to `42`. |
| 762–764, 774–780 | [processes.links](../../examples/met/thesis/processes.links) | First-order `UFork` and `Suspend` with a cooperative queue. Forwards `Note` across the scheduler and records `["start", "child", "parent", "child resumed", "parent resumed"]`. |
| 813–815, 826–828 | [handler_results.links](../../examples/met/thesis/handler_results.links), [state_result_escape.links](../../examples/met/thesis/rejected/state_result_escape.links) | `state` requires `a::Abs`. The ambient closure `() -> ()` with `Get` and `Put` in its body cannot instantiate that argument. |
| 888–894, 905–907 | [handler_results.links](../../examples/met/thesis/handler_results.links) | `state'` records `<State(s)>` in its result type. The returned closure runs in a second `State(Int)` handler and increases its state from `10` to `52`. |
| 929–932, 948–950 | [state_payload_escape.links](../../examples/met/thesis/rejected/state_payload_escape.links), [handlers.links](../../examples/met/thesis/handlers.links) | `State(s::Abs)` enforces an absolute payload for `Get` and `Put`. Rejects storing an ambient closure which would call `Yield` after leaving its `Gen` handler. |
| 993–995 | [higher_order_coop.links](../../examples/met/thesis/higher_order_coop.links) | `Fork` takes a child of type `[Coop] (() -> ())`. Parent, child and grandchild suspend once each, returning `3`. |
| 1006–1008 | Deferred | `Coop e` needs an effect variable for the independently chosen context of a child. A bare arrow shares the current context but gives the operation a non-absolute payload. A fixed absolute annotation assumes one set of additional effects. |
| 1044–1046, 1051–1053 | [handler_results.links](../../examples/met/thesis/handler_results.links) | `state` returns `List (forall a. [] (a -> a -> a))` without explicit type instantiation. Calling the returned functions at `Int`, `Bool` and `String` gives `(42, true, "second")`. |
| 1076–1100 | [pure.links](../../examples/met/thesis/pure.links), [print_list.links](../../examples/met/thesis/print_list.links), [handlers.links](../../examples/met/thesis/handlers.links) | The cheat sheet repeats the interface, absolute function and relative handler examples. Its `Fail` puts `forall a::Abs` on the operation signature. `all` discards the failing branch and returns `[42]`. |

#### Fresco effect and data examples

Source paths are relative to the Fresco artefact at revision
`333738dbe9da1dcd094a6b2c2c9dbb9eec701ea4`. SmallLinks paths are
relative to `examples/met/fresco-effects/`.

| Fresco source | SmallLinks file | Result or reason for exclusion |
| --- | --- | --- |
| `README.md:74–105` | `find_mask_paper.links` | `collected` is `[1, 2, 3]` and `found` is `Just(3)`. Includes the collector, ambient iterator and first-match search. |
| `tests/pass/effectful-empty-list.mle` | `effectful-empty-list.links` | `([], [])` at `(List Int, List Bool)`. The empty list has a polymorphic modal type. |
| `tests/pass/effectful-list.mle` | `effectful-list.links` | `[1]`. A list with a fixed context stores a callback that invokes `Yield`. |
| `tests/pass/effects-exchange.mle` | `effects-exchange.links` | `[1, 2, 3, 1, 2, 1, 2, 3, 1, 3]`. All four positive exchanges work with ordinary SmallLinks interfaces. The reference declares `e3` with `eff#`, whose row-head condition has no SmallLinks counterpart. |
| `tests/pass/extend-absolute-mod.mle` | `extend-absolute-mod.links` | `42`. Converts an absolute pure callback to one typed under `Gen`. |
| `tests/pass/find_mask_paper.mle` | `find_mask_paper.links` | `observed` is `(Just(2), [1, 2])`. The enclosing handler receives both predicate yields and the search stops at the first match. |
| `tests/pass/fresco.mle` | `fresco.links` | `((42, true), (42, true), (42, true))`. Exercises a higher-rank parameter with an annotation, one supplied by an expected type, and a producer with quantification inside an absolute modality. |
| `tests/pass/handle-do-mono.mle` | `handle-do-mono.links` | `()`. Handles a direct call of a monomorphic operation. |
| `tests/pass/handle-do-param-mono.mle` | `handle-do-param-mono.links` | `()`. Infers the interface parameter `Int` from a direct operation call. |
| `tests/pass/handle-fun-param.mle` | `handle-fun-param.links` | `()`. Handles a callback whose relative context supplies `Gen(Int)`. |
| `tests/pass/higher-order-effects.mle` | `higher-order-effects.links` | `([1, 2, 3, 5, 4, 6, 4], [1, 2, 3, 4, 5])`. Runs both FIFO schedulers, with a Boolean fork and a fork that takes a task. The queue is passed to resumptions explicitly. The latter fork has a task payload fixed at `[Trace, Coop]` to satisfy `Abs`. |
| `tests/pass/infer-lambda-do.mle` | `infer-lambda-do.links` | `()`. Infers the interface parameter from the operation in an unannotated thunk passed to a polymorphic callback. |
| `tests/pass/list-map-fold.mle` | `list-map-fold.links` | `([2, 3, 4], 123, 321, [1, 2, 3])`. Shares the context between a list helper and its callback, including an iterator called with `Gen`. |
| `tests/pass/single-yield.mle` | `single-yield.links` | `1`. A function with context `[Gen]` calls `Yield`. |
| `tests/fail/effectful-list-non-value.mle` | `rejected/effectful-list-non-value.links` | `Modal introduction requires a value`. The function call inside the list is available in `Gen`; the resulting list cannot acquire a new absolute modality. |
| `tests/fail/exchange-accidental.mle` | Excluded | Fresco's `eff#` checks that the occurrence is at the head of the remaining row during modality comparison. In SmallLinks distinct interface names commute, and the corresponding two-interface exchange is accepted. |
| `tests/fail/extend-relative-mod.mle` | `rejected/extend-relative-mod.links` | `The modalities require different effect contexts`. An ambient callback cannot acquire a relative `Gen` requirement. |
| `tests/fail/handle-do-param-mismatch.mle` | `rejected/handle-do-param-mismatch.links` | `Expected (), got Int`. The operation clause returns the `Yield` argument where the result must be unit. |
| `tests/fail/handle-fun-mismatch.mle` | `rejected/handle-fun-mismatch.links` | `Expected (), got Int`. The operation clause must also agree with the unit result when the computation is a callback. |
| `tests/fail/leak-effect-paper.mle` | `rejected/leak-effect-paper.links` | `Cannot call a value of type <Gen \|> (_)`. Calling the predicate across the handler lock would let its effects reach the inner handler. |
| `tests/fail/limitation-infer-find-paper.mle` | Excluded | This tests inference for an unannotated callback called under a term mask. SmallLinks has no term mask. The predicate-operation translation invokes the callback in its original context and infers the unannotated definition successfully. |
| `tests/fail/pure-id-fun.mle` | `rejected/pure-id-fun.links` | `must satisfy Abs`. The bare arrow inferred for the lambda does not satisfy the absolute type argument. |
| `tests/fail/relative-to-absolute.mle` | `rejected/relative-to-absolute.links` | `Cannot access f across the change in effect context`. A relative `Gen` callback cannot be returned at the fixed absolute context. |
| `tests/fail/two-do-mismatch.mle` | `rejected/two-do-mismatch.links` | `Expected (\|First\|), got (\|Second\|)`. Both calls must use the same `Gen` instance, so the two closed variant types are incompatible. |

The search examples implement the effect of masking at the predicate
call by requesting evaluation through a `Predicate(a)` operation. Its
handler clause calls the predicate in the caller's context. The loop
runs under both `Gen(a)` and `Predicate(a)`. It keeps the predicate's
evaluation order and early termination, including when the caller
handles a separate `Gen(a)` instance. This preserves shared ambient
contexts without adding a general term mask.

The source higher-order scheduler's `eff# state s` allows the state
type `s` to contain ambient functions. SmallLinks requires absolute
operation payloads and absolute handler state parameters. Passing the
queue through the resumptions as an ordinary argument keeps those
functions in their ambient context. The absolute `Fork` payload fixes
the set of effects available to a child task.

#### Larger Fresco programs

Source paths are relative to the Fresco artefact. Each result below is
one component of the corresponding SmallLinks program's output.

| Source | SmallLinks file | Result |
| --- | --- | --- |
| `tests/pass/unix.mle:4–52` | [unix.links](../../examples/met/fresco-programs/unix.links) | `(1, "dead")`. The simulated descriptor `FD(1)` supplies the source's declaration of `stdout`. Exit discards the suffix after it. |
| `tests/pass/unix.mle:54–91` | `unix.links` | Standalone lookup returns `"lucile"`. The session example returns `(0, "alice bob root ")`. A parameterised handler handles `AskUser` and `Su` together and passes the new user to the resumption. The source's `mask<ask>` syntax requires a deferred term mask. |
| `tests/pass/unix.mle:93–121` | `unix.links` | Multi-shot `Fork` returns both statuses `[0, 0]` and collects all of Ritchie's output followed by Hamlet's. |
| `tests/pass/unix.mle:123–152` | `unix.links` | The scheduler resumes two paused branches and returns `([2, 1], "")`. The finished list accumulates each result at the front. |
| `tests/pass/unix.mle:154–167` | `unix.links` | Both statuses are `[0, 0]`. An interruption before each write makes the scheduler alternate the two outputs until Hamlet finishes. |
| `tests/pass/unix.mle:169–184` | `unix.links` | The parameterised `State` interface and state-threading handler return `(40, 42)`. |
| `tests/pass/faux-tt.mle:3–198` | [faux-tt.links](../../examples/met/fresco-programs/faux-tt.links) | Recursive syntax and terms, occurrence checking, a fresh ID supply, polymorphic errors, and a scoped store of metavariables. These support both elaboration demonstrations below. |
| `tests/pass/faux-tt.mle:200–378` | `faux-tt.links` | Capture-avoiding substitution, normalisation and unification. In the hole demonstration unification solves the metavariable with `Type`. |
| `tests/pass/faux-tt.mle:381–468` | `faux-tt.links` | The checked identity elaborates to `Lam(0, Type, Lam(2, Var(0), Var(2)))`. An ascription with a hole infers `(Type, Type)`, the elaborated term and its inferred type. [EXAMPLE_ISSUES.md](EXAMPLE_ISSUES.md) records a defect in the source application rule. |

#### Fresco typing cases

Sources are relative to the artefact's `tests/fresco/`. SmallLinks
programs are relative to `examples/met/fresco-types/`. The artefact
tests 57 files at revision `333738dbe9da1dcd094a6b2c2c9dbb9eec701ea4`.
The table tracks 75 accepted and 20 rejected source subcases, including
the Church-list rejections tested in isolation. A runtime result in
the table refers to the indicated component of the program's output.

| Source and subcase | SmallLinks program and binding | SmallLinks result |
| --- | --- | --- |
| `pass/a1.mle` infer | `choice.links` `inferredSecond` | Inferred curried projection. Returns `42`. |
| `pass/a1.mle` check | `choice.links` `checkedSecond` | Checks the signed projection. Returns `true`. |
| `pass/a2.mle` infer | `choice.links` `inferredChoice` | The identity's type is instantiated. Applying the result returns `42`. |
| `pass/a2.mle` check | `choice.links` `checkedChoice` | Checks at `Id -> Id`. Applying the result returns `true`. |
| `pass/a3.mle` infer | `native-lists.links` `inferredChoice` | Returns a list of two polymorphic identities. |
| `pass/a3.mle` check | `native-lists.links` `checkedChoice` | Checks at `List Id` and has length `2`. |
| `pass/a4.mle` | `choice.links` `selfApply` | Inferred self-application of an annotated polymorphic argument. Applying the result returns `42`. |
| `pass/a5.mle` infer | `choice.links` `inferredAuto` | Infers a function that takes and returns `Id`. Applying the result returns `42`. |
| `pass/a5.mle` check | `choice.links` `checkedAuto` | Checks at `Id -> Id`. Applying the result returns `true`. |
| `pass/a6.mle` | `choice.links` `specialisedAuto` | Infers the result with the outer type argument of `autoPrime` instantiated. Applying it returns `42`. |
| `pass/a7.mle` infer | `choice.links` `inferredAutoChoice` | Infers the higher-rank function type from `auto`. Applying the result returns `42`. |
| `pass/a7.mle` check | `choice.links` `checkedAutoChoice` | Checks at `Id -> Id`. Applying the result returns `true`. |
| `pass/a9.mle` native | `native-list-results.links` `chosenFunction` | Returns a polymorphic identity. Applying it returns `42`. |
| `pass/a9.mle` Church | `church-list-results.links` `chosenFunction` | Returns a polymorphic identity. Applying it returns `42`. |
| `pass/a10.mle` A10a | `application.links` `named` | `(42, true)` from a named argument. |
| `pass/a10.mle` A10b | `application.links` `lambda` | `(42, true)` from a lambda argument. |
| `pass/a10.mle` A10c | `application.links` `viaIdent` | `(42, true)` after applying identity to a higher-rank consumer. |
| `pass/a11.mle` native | `native-list-results.links` `sharedType` | The list supplies the lambda's parameter type. Returns `1`. |
| `pass/a11.mle` Church | `church-list-results.links` `sharedType` | The fold supplies the lambda's parameter type. Returns `1`. |
| `pass/a12.mle` A12a | `application.links` `forward` | `(42, true)` using application. |
| `pass/a12.mle` A12b | `application.links` `backward` | `(42, true)` using reverse application. |
| `pass/a13.mle` A13a | `rank-two.links` `forwardST` | `42` using `app` with a state-polymorphic value. |
| `pass/a13.mle` A13b | `rank-two.links` `backwardST` | `42` using `revapp` with a state-polymorphic value. |
| `pass/b1.mle` B1a native | `native-lists.links` `rest` | Tail retains type `List Id` and has length `1`. |
| `pass/b1.mle` B1b native | `native-lists.links` `first` | Head has type `Id` and returns `42` and `true` at the two uses. |
| `pass/b1.mle` B1c native | `native-lists.links` `one` | Singleton instantiates the identity. Calling its head returns `42`. |
| `pass/b1.mle` B1a Church | `church-lists.links` `rest` | Tail retains type `Church(Id)` and has length `1`. |
| `pass/b1.mle` B1b Church | `church-lists.links` `first` | Head has type `Id` and returns `42` and `true` at the two uses. |
| `pass/b1.mle` B1c Church | `church-lists.links` `one` | Singleton instantiates the identity. Calling its head returns `42`. |
| `pass/b2.mle` native | `native-lists.links` `withName` | Prepends a named identity at type `Id`. Length `3`. |
| `pass/b2.mle` Church | `church-lists.links` `withName` | Prepends a named identity at type `Id`. Length `3`. |
| `pass/b3.mle` native | `native-lists.links` `withLambda` | Prepends a lambda checked at `Id`. Length `3`. |
| `pass/b3.mle` Church | `church-lists.links` `withLambda` | Prepends a lambda checked at `Id`. Length `3`. |
| `pass/b4.mle` native | `native-lists.links` `ints` | Infers integer functions from two singleton calls. Applying them returns `[42, 41]`. |
| `pass/b4.mle` Church | `church-lists.links` `ints` | Infers integer functions from two singleton calls. Applying them returns `[42, 41]`. |
| `pass/b5.mle` native | `native-lists.links` `moreIds` | Appends a singleton at `List Id`. Length `3`. |
| `pass/b5.mle` Church | `church-lists.links` `moreIds` | Appends a singleton at `Church(Id)`. Length `3`. |
| `pass/b6.mle` native | `native-lists.links` `mappedSingleton` | `[(42, true)]` from mapping a higher-rank consumer over a singleton. |
| `pass/b6.mle` Church | `church-lists.links` `mappedSingleton` | A Church singleton of `(42, true)`, converted to `[(42, true)]`. |
| `pass/b8.mle` native | `native-lists.links` `appliedHead` | Calls the polymorphic head and returns `true`. |
| `pass/b8.mle` Church | `church-lists.links` `appliedHead` | Calls the polymorphic head and returns `true`. |
| `pass/beta1.mle` | `application.links` `returnedApp` | `(42, true)` via an application function returned by a lambda. |
| `pass/beta3.mle` | `application.links` `returnedArgument` | `(42, true)` with a higher-rank argument returned by a lambda. |
| `pass/c1b.mle` | `rank-two.links` `useBoth` | An annotated parameter can be used at both types. Returns `(42, true)`. |
| `pass/c1c.mle` | `rank-two.links` `checkedLambda` | The expected type supplies the polymorphic parameter. Returns `()`. |
| `pass/c2.mle` | `rank-two.links` `nestedQuantifiers` | Checks the lambda with a quantifier before each arrow. Returns `42`. |
| `pass/e1b.mle` native | `native-list-results.links` `etaExpanded` | Checks the lambda against a type quantified before its `Int` argument. Applying it returns `true`. |
| `pass/e1b.mle` Church | `church-list-results.links` `etaExpanded` | Checks the lambda against a type quantified before its `Int` argument. Applying it returns `true`. |
| `pass/e2b.mle` | `rank-two.links` `consume` | The signature supplies the higher-rank parameter, returning `(42, true)`. |
| `pass/e3a.mle` | `application.links` `forward` | Same expression as A12a. Returns `(42, true)`. |
| `pass/e3b.mle` | `application.links` `frozenArgument` | Freezing supplies the polymorphic parameter to the lambda. Returns `(42, true)`. |
| `pass/e4a.mle` native | `native-lists.links` `mappedName` | `[(42, true), (42, true)]` from mapping a named consumer. |
| `pass/e4a.mle` Church | `church-lists.links` `mappedName` | Maps a named consumer. Converts to `[(42, true), (42, true)]`. |
| `pass/e4b.mle` native | `native-lists.links` `mappedLambda` | `[(42, true), (42, true)]` from mapping a lambda. |
| `pass/e4b.mle` Church | `church-lists.links` `mappedLambda` | Maps a lambda. Converts to `[(42, true), (42, true)]`. |
| `pass/e6.mle` | `application.links` `returnedPartial` | `(42, true)` after returning a partial application from a lambda. |
| `pass/e7.mle` | `application.links` `passedToLambda` | A frozen identity gives the lambda a polymorphic parameter. Returns `(42, true)`. |
| `pass/f1.mle` native | `native-lists.links` `mappedTwice` | `[(true, 42), (true, 42)]` from mapping a lambda that calls each element at two types. |
| `pass/f1.mle` Church | `church-lists.links` `mappedTwice` | Maps a lambda that calls each element at two types. Converts to `[(true, 42), (true, 42)]`. |
| `pass/f2.mle` | `application.links` `viaApp` | Calls both instantiations via `app`. Returns `(true, 42)`. |
| `pass/f4.mle` | `application.links` `direct` | Calls both instantiations via direct application. Returns `(42, true)`. |
| `pass/f5.mle` | `application.links` `checkedPair` | Checks the function against the pair's expected type. Observed as `(42, 42)`. |
| `pass/f6.mle` | `church-list-results.links` `chosenList` | Infers a fold with its accumulator type instantiated. Counting the elements returns `2`. |
| `pass/f7.mle` Church | `church-list-results.links` `chosenHead` | Freezing retains the Church fold's quantifier. Applying the selected identity returns `42`. |
| `pass/f7.mle` native | `native-list-results.links` `chosenHead` | The native list retains its polymorphic element type. Applying the selected identity returns `42`. |
| `pass/f8.mle` native | `native-list-results.links` `fromIntCallback` | The callback returns `List Id`. Its consumer returns `(42, true)`. |
| `pass/f8.mle` Church | `church-list-results.links` `fromIntCallback` | Returns a fold with an instantiated accumulator. Counting returns `2`. |
| `pass/f9.mle` native | `native-list-results.links` `fromPairCallback` | The callback returns a pair with `List Id` in the second component. Its consumer returns `(42, true)`. |
| `pass/f9.mle` Church | `church-list-results.links` `fromPairCallback` and `blocked/church-pair-result.links` | Folding the result at `Int` returns `2` in both modes. The standalone expression passes the default checker and fails frontend rechecking when the accumulator remains unconstrained. |
| `pass/f10.mle` native | `native-list-results.links` `fromIdCallback` | A callback takes `Id` and returns `List Id`. Its consumer returns `(42, true)`. |
| `pass/f10.mle` Church | `church-list-results.links` `fromIdCallback` | A callback takes `Id` and returns a fold with an instantiated accumulator. Counting returns `2`. |
| `pass/f11a.mle` native | `native-list-results.links` `checkedCall` | The expected type of the singleton retains `Id`. Returns `(42, true)`. |
| `pass/f11a.mle` Church | `church-list-results.links` `checkedCall` | The expected type of the singleton retains `Id`. Returns `(42, true)`. |
| `pass/f11b.mle` native | `native-list-results.links` `frozenCall` | The frozen identity retains `Id` in the bound singleton. Returns `(42, true)`. |
| `pass/f11b.mle` Church | `church-list-results.links` `frozenCall` | The frozen identity retains `Id` in the bound singleton. Returns `(42, true)`. |
| `fail/a8.mle` | `rejected/choice-polymorphic-result.links` | Rejects the mismatch between a polymorphic result and an instantiated result of `autoPrime`. |
| `fail/b7.mle` native | `inference-differences.links` `mappedHeads` | SmallLinks accepts the inferred list of polymorphic identities. Its consumer returns `(42, true)`. |
| `fail/b7.mle` Church | `rejected/church-map-head.links` | Rejects the element type of the nested fold without the expected polymorphic identity type. |
| `fail/c1a.mle` | `rejected/unannotated-polymorphic-parameter.links` | Rejects the `Bool` call after inferring an `Int` parameter. |
| `fail/e1a.mle` native | `rejected/list-quantifier-placement.links` | Rejects the quantifier in `h`'s result against a type quantified before its argument. |
| `fail/e1a.mle` Church | `rejected/church-quantifier-placement.links` | Rejects the quantifier in `h`'s result against a type quantified before its argument. |
| `fail/e2a.mle` | `rejected/unannotated-poly-consumer.links` | Rejects the unknown parameter type where `poly` needs `Id`. |
| `fail/e3b.mle` | `rejected/application-unfrozen-argument.links` | Rejects the inferred parameter because a quantified variable would escape its scope. |
| `fail/e5a.mle` native | `inference-differences.links` `consumeHead` | SmallLinks infers that the composition takes `List Id`. Applying it returns `(42, true)`. |
| `fail/e5a.mle` Church | `inference-differences.links` `consumeChurchHead` | SmallLinks infers that the composition takes `Church(Id)`. Applying it returns `(42, true)`. |
| `fail/e5b.mle` native | `rejected/unannotated-list-parameter.links` | Rejects the unknown parameter type where `head` needs `List Id`. |
| `fail/e5b.mle` Church | `rejected/unannotated-church-parameter.links` | Rejects the unknown parameter type where `churchHead` needs a polymorphic fold. |
| `fail/e7.mle` | `rejected/lambda-unfrozen-argument.links` | Rejects the inferred parameter because a quantified variable would escape its scope. |
| `fail/f2.mle` | `rejected/apply-unfrozen-identity.links` | Rejects the `Int` call after inferring a `Bool` parameter. |
| `fail/f3.mle` native | `inference-differences.links` `mappedIds` | SmallLinks instantiates the mapping identity at `Id`. Its consumer returns `(42, true)`. |
| `fail/f3.mle` Church | `inference-differences.links` `mappedChurchIds` | SmallLinks instantiates the mapping identity at `Id`. Its consumer returns `(42, true)`. |
| `fail/f4.mle` | `rejected/call-unfrozen-identity.links` | Rejects the `Bool` call after inferring an `Int` parameter. |
| `fail/f7.mle` | `inference-differences.links` `chosenHead` | SmallLinks accepts the unfrozen Church argument. The result is an identity called at `Int` and `Bool`, yielding `(42, true)`. |
| `fail/f11b.mle` native | `rejected/bound-singleton.links` | Rejects the list of instantiated identities where a list of polymorphic identities is required. |
| `fail/f11b.mle` Church | `rejected/bound-church-singleton.links` | Rejects the fold over instantiated identities where a fold over polymorphic identities is required. |

The commented-out `check` proposals in `pass/a4.mle`, `pass/a6.mle`,
`pass/a9.mle` and `fail/a8.mle` are inactive in the artefact. Standalone
`val` declarations were supplied with definitions for the runnable
examples. In A13 the `Test` constructor carries the result `a`, so
`runST` can return that value while the unused state type `s` remains
universally quantified.

### Example verification

The examples, registrations and documentation are complete. The
standalone Church case in `blocked/` is a reproducer. See
[EXAMPLE_ISSUES.md](EXAMPLE_ISSUES.md#frontend-rechecking-fails-for-a-callback-pair-with-an-unconstrained-result).
The [thesis inventory](#thesis-tutorial) records the deferred generic
`Coop e` interface and the two adaptations for term masks. The
[Fresco inventory](#fresco-effect-and-data-examples) records the two
excluded rejection cases.

Combined checks used SmallLinks compiler revision
`7b764a87e6414b46de8feb00c2de0c8c704dbca2` with OCaml 5.4.0.
The logs and temporary configs below are under
`/private/tmp/smalllinks-met-examples/` unless a path is given.

| Command | Result | Log |
| --- | --- | --- |
| `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk make all-ci` | Built the compiler and example installation files. | `ci-build.log` |
| `make tests` | 1,327 passed across 43 suites, with two existing ignores. All six scripts passed. The example typecheck suite passed all 94 entries, including 60 new ones. | `all-tests.log` |
| `./test-harness tests/met_examples.tests /private/tmp/smalllinks-met-examples/strict.config` | All 31 runnable examples gave the expected output with frontend rechecking and strict IR checking. | `strict-runtime.log` |
| `./test-harness /private/tmp/smalllinks-met-examples/strict-rejections.tests /private/tmp/smalllinks-met-examples/strict-rejections.config` | All 28 negative examples produced their expected type errors with the strict flags enabled. | `strict-rejections.log` |
| `./links` on `blocked/church-pair-result.links`, with default, IR-only and frontend-rechecking settings | Default and IR-only runs succeeded. Frontend rechecking reproduced `Type abstraction needs a type annotation`. | `known-frontend.log` |
| `opam exec -- dune install --profile=ci --prefix="$prefix" links`, `./tests/check-install.sh "$prefix/bin/linx"` and `python3 /private/tmp/smalllinks-met-examples/installed.py` | Installed files matched the checkout. All 60 installed examples produced the expected result or rejection from outside the checkout. | `install.log`, `install-check.log`, `installed-examples.log` |
| `./links --config=/private/tmp/smalllinks-met-examples/strict.config examples/met/fresco-effects/find_mask_paper.links` | The new guide reference produced the list, first match and outer predicate yields shown in the inventory. | `guide-search.log` |
| `make rule-check`, `git diff --check` and `python3 /private/tmp/smalllinks-met-examples/check-docs.py` | Passed. The Python check covered whitespace, including tabs after the GNU find check was skipped, plus links, source coverage and registrations. | `rule-check.log`, `diff-check.log`, `documents.log` |
| Fresco `./test.sh bin/met.exe tests/` and `./test.sh bin/met.exe tests/fresco` | The reference implementation reported zero failures in 25 effect and data tests and 57 typing tests. | `/tmp/met-fresco-effects-reference.log`, `/tmp/met-fresco-artifact-tests.log` |
