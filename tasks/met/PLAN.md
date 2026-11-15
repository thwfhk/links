# SmallLinks modal effect types plan

The language design and scope are in [SPEC.md](SPEC.md#scope).
This plan records milestones, dependencies, progress and checks.
[IMPL.md](IMPL.md) records significant implementation decisions.

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

## Chat handovers

Use four chats in this order:

1. Milestones 1–2: finish the design review, record the baseline, and
   implement syntax and type representation.
2. Milestone 3: implement Fresco inference and modal types.
3. Milestone 4: implement operation, handler and native-effect typing.
4. Milestones 5–6: integrate the compiler, migrate libraries and tests,
   review the combined changes and run final checks.

Each chat reads the latest SPEC.md, PLAN.md and IMPL.md before starting.
Use the same `small-met` branch and finish the preceding work before
starting the next chat's implementation. At handover, update this plan
with completed items, commits, checks, next action and blockers, and
record implementation decisions in IMPL.md.

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
  interface member signatures and handler clause annotations. Reject
  nested list and modal element types without parentheses, and migrate
  any affected source or printer output. Test both unary arrow forms,
  `List A` and `List(A)`, the reserved `effect` keyword and the rejection
  of empty interfaces.
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
  types from handled expressions and clauses before choosing an
  instance. Check that reordering equally valid constraints produces
  the same type or the same request for an annotation. Cover known
  types in branches, local value bindings and local function bodies.
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
  that forward the handler input in every branch. Test a return through
  a pattern alias and a shadowing binding that returns a different value.
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
  checks on the new revision. Keep the results from 6.5 as a record of
  the earlier run.
- [x] **6.7** (`f9d190ef`) Review 5.20 independently and run the combined
  checks on the new revision. Keep the results from 6.5 and 6.6 as
  historical checks.

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

The first implementation is complete on `small-met`. The native compiler
uses Fresco for files, expressions and REPL sentences. The [migration
inventory](MIGRATION.md) records the retained and deferred cases.

The final review fixes for milestones 2–4 are complete. Commit
`67f8eded` extends frozen argument inference to polymorphic `do` calls.
Items 3.13 and 3.14 cover argument inference and conditional branches.
Item 2.8 is complete at `66861cb0`. Items 4.11–4.13 cover return
annotations, forwarding switches and conflicting interface arguments.
The final review of milestone 5 completed 5.14 at `85ad25b5`. The
record, polymorphism and collection suites passed with 43, 70 and 61
cases after `make`. Logs are in `/private/tmp/smalllinks-met-5-14/`.
Item 5.15 passed all 10 REPL checks with default settings and with
frontend rechecking and strict IR checks. Logs are in
`/private/tmp/smalllinks-met-5-15/`. Item 5.16 passed the 66 collection,
three frontend recheck and 30 typed IR tests. Logs are in
`/private/tmp/smalllinks-met-5-16/`. Item 5.17 passed the 69 collection
and 58 module tests, with additional checks of source order, nesting
and shadowing. Logs are in `/private/tmp/smalllinks-met-5-17/`.
Item 5.18 passed the full strict handler suite, including `(-Tag as x)`,
and the pattern suite with both default and strict settings. Logs are
in `/private/tmp/smalllinks-met-5-18/`. The
[combined checks in 6.5](#milestone-65-checks) passed on `66ee9476`.
Item 5.19 passed both reported probes with default and strict settings.
The [combined checks in 6.6](#milestone-66-checks) passed on `5e971724`.
Item 5.20 passed the enclosing alias, annotation and record rest probes
under default and strict settings. The
[combined checks in 6.7](#milestone-67-checks) passed on `f9d190ef`.
The milestone 3 design review is complete. The current checker matches
the reviewed rules. See the [design checks](#milestone-3-design-checks)
and the [future work](SPEC.md#future-work) for inference and type holes.
Items 5.5 and 5.7–5.13 share the compiler and library commit
`7f1f3f8c` because the startup, frontend and IR changes share code and
checks. Commit `4b63194d` keeps source preprocessing off the bundled
comprehension helpers. The final guide and verification record cover
the combined revision. Optimisation work remains in the
[deferred list](IMPL.md#deferred-optimisation-issues).

### Milestone 3 design checks

| Revision and command | Result | Log |
| --- | --- | --- |
| SmallLinks `f1b8b80e`, `make` and `./links -e` with frontend rechecking and strict IR checks | Build and all 15 probes passed. Both modal argument orders asked for an annotation. The signed recursive calls and quantified record examples passed. `%` in aliases and signatures was rejected. | `/private/tmp/met-reviewed-design.zvoKtw/build.log`, `probes.log` |
| SmallLinks `f1b8b80e`, `./test-harness` on `handlers`, `effect_annotations`, `polymorphism`, `records` and `desugar_datatypes` | 407 tests passed across the five suites. | `/private/tmp/met-reviewed-design.zvoKtw/`, `<suite>.log` |
| `make rule-check`, `git diff --check`, document link check and `rg` tab scan | Passed. The tab scan covered the source files checked by the GNU find rule. | `/private/tmp/met-reviewed-design.zvoKtw/`, `rule-check.log`, `diff-check.log`, `documents.log`, `tabs.log` |
| Links `4e5c78c5` and SmallLinks `4407a649`, `./links -e` in separate builds | Both accepted `%` in aliases. Direct uses shared one type variable. An eligible binding could generalise that variable. | `/private/tmp/met-alias-history.gdyiZZ/`, `*-probes.log`, `*-alias-binding-probes.log` |
| Links `1912d9b7` and SmallLinks `4407a649`, `./links -e` in separate builds | Both solved and generalised signature holes. Links rejected an unresolved hole beside explicit `forall` with `Inconsistent quantifiers`. SmallLinks generalised it. | `/private/tmp/met-signature-history.mDhCUw/1912d9b7-refined-signature-probes.log`, `4407a649-signature-probes.log` |

### Milestone 4 final review checks

The combined checks used `6c054ee5` with OCaml 5.4.0. Logs are in
`/private/tmp/smalllinks-met-4-defects.DqKn6y/`. Independent review checked redundant
annotations, changes to the type of a returned value, switch scope and
pattern narrowing, and the difference between an incompatible type and
an unresolved choice of modality. See `4.11-independent-review.log`,
`4.12-independent-review.log` and `4.13-probes.log`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` for each fix and `make all-ci` on the combined revision | Passed. | `4.1*-build.log`, `ci-build.log` |
| `make tests` | 1,183 passed across 42 suites, with two existing ignored cases. All four scripts passed. | `all-tests.log` |
| `./test-harness` on the affected suites | Passed, including 152 handler, 76 effect annotation, 70 polymorphism, 34 example and 30 typed IR cases. | `<suite>.log` |
| `opam exec -- ./run-tests unit-tests` | All 105 passed. | `unit-tests.log` |
| Handler and effect annotation tests with frontend rechecking and strict IR checks | 151 handler and 76 effect annotation cases passed. | `strict-handlers.log`, `strict-effect_annotations.log` |
| Handler example runner with strict checking and a typecheck-only example | Passed. | `strict-examples.log`, `typecheck-only.log` |
| `make rule-check`, `git diff --check` and the `rg` tabs check | Passed. GNU find was unavailable for the tabs rule. | `rule-check.log`, `diff-check.log`, `tabs.log` |

That strict handler run excluded the negative variant alias
`(-Tag as x)` probe. It passes with default settings. Strict IR
checking reported the same mismatch at its narrowed binder on
`5c6eab2a` and `6c054ee5` (`4.12-refining-pattern-strict.log`). Item 5.18
fixes it and runs the full strict handler suite.

### Milestone 2 final review checks

The checks used `66861cb0` with OCaml 5.4.0. Logs are in
`/private/tmp/smalllinks-met-28.1zXgOH/`. Independent review checked
alias scopes, the REPL and recursive expansions. Its findings led to
tests for renamed binders, unused alias parameters and arguments that
grow while unfolding. See [2.8](IMPL.md#28-shadowed-type-aliases) for
the printing limits.

| Command or check | Result | Log |
| --- | --- | --- |
| `make all-ci` | Passed. | `final-ci-build.log` |
| `make tests` | 1,162 passed across 42 suites, with two existing ignored cases. All four scripts passed, including 32 print-and-reparse checks. | `final-all-tests.log` |
| `./test-harness` on `handlers`, `effect_annotations`, `polymorphism`, `typecheck_examples`, `roundtrippable_types` and `modules` | 131, 76, 70, 34, 18 and 57 passed. | `<suite>.log` |
| `opam exec -- ./run-tests unit-tests` | All 105 passed. | `unit-tests.log` |
| Handler aggregate with frontend rechecking and strict IR checks | All nine assertions passed. | `strict-handlers.log` |
| Temporary CI installation and `./tests/check-install.sh "$prefix/bin/linx"` | Passed. The installed interpreter also expanded a shadowed modal alias from outside the checkout. | `install.log`, `install-check.log` |
| Both printers on the review probes and a REPL alias listing | Passed. The growing alias showed the out-of-scope marker and the unused parameter case printed a `mu` type. | `review-probes.log` |
| `make rule-check`, `git diff --check` and the `rg` tabs check | Passed. GNU find was unavailable for the tabs rule. | `rule-check.log`, `diff-check.log`, `tabs.log` |

### Milestone 3 final review checks

The polymorphic `do` fix (`67f8eded`) was checked before committing.
Logs are in `/private/tmp/met-stage3-late.bXtyC2/`.
`make` passed (`make.log`). `make tests` passed 1,138 tests in 42 suites
and all four scripts, with two existing ignored tests (`all-tests.log`).
The 105 IR unit tests passed (`unit-tests.log`). The probes confirmed
the signed recursive example with a branch ascription, quantified
record projection and the alias hole rejection (`spec-probes.log`).
`make rule-check`, the `rg` tab scan, `git diff --check` and the
document link check passed (`rule-check.log`, `tabs.log`,
`diff-check.log`, `documents.log`).

The combined checks used `fadf5af7` and OCaml 5.4.0. Logs are in
`/private/tmp/met-stage3-final.JGgUkp/`. Independent review checked
fixed results, frozen fields, record extensions and updates, branch
typing and the value restriction. Review caught a partial inference
failure in argument blocks that have an annotated local binding.
The fix leaves that case to full checking, and a regression covers it.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` on `3a631692` and `fadf5af7`, then `make all-ci` on `fadf5af7` | Passed. | `3.13-confirm-build.log`, `3.14-build.log`, `final-ci-build.log` |
| `make tests` | 1,153 passed across 42 suites. Two existing cases were ignored. All four scripts passed. | `final-all-tests.log` |
| `./test-harness` on the affected suites in [Checks](#checks) | Passed. This includes 131 handler, 76 effect annotation, 70 polymorphism, 67 FreezeML and 34 example tests. | `final-<suite>.log` |
| `opam exec -- ./run-tests unit-tests` | All 105 passed. | `final-unit-tests.log` |
| Handler aggregate with frontend rechecking and strict IR checks | All nine assertions passed. | `final-strict-handlers.log` |
| `./links -e`, file execution with an import and `--set=typecheck_only=true` | Passed. | `final-entry-points.log` |
| `opam exec -- dune install --profile=ci --prefix="$prefix" links` and `./tests/check-install.sh "$prefix/bin/linx"` | Passed. The installed interpreter ran the modal handler and the signed recursive example outside the checkout. | `final-install.log`, `final-install-test.log`, `final-installed-examples.log` |
| `make rule-check`, `git diff --check`, document links and the `rg` tab scan | Passed. The scan replaced the tabs rule on macOS because GNU find was unavailable. | `rule-check.log`, `diff-check.log`, `documents.log`, `tabs.log` |

### Milestones 5–6 follow-up checks

The combined source revision was `4b63194d` with OCaml 5.4.0.
Logs are in `/private/tmp/smalllinks-met-56-follow-up/`.
Independent review covered interface scopes, linear list splitting,
REPL recovery, comparisons and comprehension lowering. The review
fixes retain the usual precedence of a scoped comparison and preserve
a modal generator's element type through frontend rechecking.

| Command or check | Result | Log |
| --- | --- | --- |
| `make all-ci` with a fresh Dune build directory | Passed. The macOS build used `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`. | `final-clean-ci-build.log` |
| `make tests` | 1,136 passed across 42 suites. Two existing cases were ignored. All four scripts passed, including both REPL scripts, print and reparse, and example registration. | `final-all-tests.log` |
| `opam exec -- ./run-tests unit-tests` | 105 passed. | `final-unit.log` |
| `./test-harness tests/<suite>.tests` with frontend rechecking and strict IR checks | Passed for `records` (39), `collections` (61), `operators` (27), `handlers` (131), `effect_annotations` (63), `native` (76), `modules` (57) and `library` (7). | `final-strict-<suite>.log` |
| `./test-harness tests/typed_ir.tests` and `./test-harness tests/recheck_frontend_transformations.tests` | 30 and 3 passed. Includes the matching and mismatched upcast arities. | `final-typed-ir.log`, `final-recheck.log` |
| Guide code blocks and entry points, plus the handler aggregate under strict checks | All 18 runnable guide blocks and four entry point checks passed. All nine handler assertions passed. | `final-guide.log`, `final-strict-examples.log` |
| `opam exec -- dune install --profile=ci --prefix="$prefix" links` and `./tests/check-install.sh "$prefix/bin/linx"` | Passed from the fresh build. Outside the checkout the installed interpreter ran the import, empty-prelude comprehension, modal handler and polymorphic examples. | `final-clean-install.log`, `final-clean-install-check.log`, `final-installed-examples.log` |
| `make rule-check`, `git diff --check` and document links | Passed. An `rg` scan covered the tabs rule because GNU find was unavailable. | `final-rule-check.log`, `final-diff-check.log`, `final-tabs.log`, `final-documents.log` |

### Milestone 6.5 checks

The combined checks used `66ee9476` with OCaml 5.4.0. Logs are
in `/private/tmp/smalllinks-met-56-defects/`. The independent review
found that a generated comprehension alias retained the full variant
type after a negative pattern narrowed it. The fix removed the unused
alias and added a strict regression for the source pattern. The CI
build also caught constructor names that needed to be in scope in the
REPL lowering helper. See `combined-repl-review.log` and
`ci-build-before-review-fixes.log`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make all-ci`, including a fresh Dune build directory | Passed. The macOS builds used `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`. | `final-ci-build.log`, `final-clean-ci-build.log` |
| `make tests` | 1,201 passed across 42 suites. Two existing cases were ignored. All four scripts passed. | `all-tests.log` |
| `./test-harness tests/<suite>.tests` on affected suites | All passed, including 70 collection, 58 module, 34 example, 30 typed IR and three frontend recheck tests. | `default-<suite>.log` |
| `./test-harness tests/<suite>.tests` with frontend rechecking and strict IR checks | Passed for handlers (152), effect annotations (76), collections (70), modules (58), records (43) and patterns (38). All ten handler REPL checks and all nine handler example assertions also passed under strict settings. | `strict-<suite>.log`, `strict-repl.log`, `strict-examples.log` |
| `opam exec -- ./run-tests unit-tests` | All 105 passed. | `unit-tests.log` |
| Guide examples and entry points | Passed for 18 runnable blocks, `-e`, file execution, typecheck-only execution and the REPL. | `guide.log` |
| `opam exec -- dune install --profile=ci --prefix="$prefix" links` from the fresh build and `./tests/check-install.sh "$prefix/bin/linx"` | Passed. The installed interpreter also ran the modal handler, polymorphic identity and generator-shadowing examples outside the checkout. | `install.log`, `install-check.log`, `installed-examples.log` |
| `make rule-check`, `git diff --check`, the tabs scan and document links | Passed. An `rg` scan covered the tabs rule because GNU find was unavailable. | `rule-check.log`, `diff-check.log`, `tabs.log`, `documents.log` |

At that revision, strict IR rejected a list or variant subpattern when
the value it matched was quantified. Both probes used a field of a
quantified record and returned `(42, true)` with default settings. See
`quantified-list-variant-probes.log` and follow-up item 5.19.

### Milestone 6.6 checks

The combined checks used `5e971724` with OCaml 5.4.0. Logs are
in `/private/tmp/smalllinks-met-5-19/`. Independent review checked
quantifier scope, case fallthrough, source linearity and captures in
local functions. See `independent-review-probes.log`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make all-ci`, including a fresh Dune build directory | Passed with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`. | `final-ci-build.log`, `final-clean-ci-build.log` |
| `make tests` | 1,209 passed across 42 suites. Two existing cases were ignored. All four scripts passed. | `all-tests.log` |
| `./test-harness tests/<suite>.tests` on affected suites | All passed, including 51 records, 38 patterns, 28 variants and 30 typed IR tests. | `default-<suite>.log` |
| Frontend rechecking and strict IR checks | Passed for handlers (152), effect annotations (76), collections (70), modules (58), records (51) and patterns (38). The strict handler REPL and example runner also passed. | `strict-<suite>.log`, `strict-repl.log`, `strict-examples.log` |
| `opam exec -- ./run-tests unit-tests` | All 105 passed. | `unit-tests.log` |
| Direct `./links -e` probes with default and strict settings | Both reported cases returned `(42, true)`. The additional fallback, quantified row and linearity probes passed. | `final-direct-probes.log`, `final-linearity-probes.log` |
| Guide and temporary installation | All 18 runnable guide blocks and four entry points passed. `dune install` from the fresh CI build and `./tests/check-install.sh` passed. The installed interpreter passed both reported probes under default and strict settings. | `guide.log`, `install.log`, `install-check.log`, `installed-examples.log`, `installed-pattern-probes.log` |
| `make rule-check`, `git diff --check`, tabs and document links | Passed. An `rg` scan covered the tabs rule because GNU find was unavailable. | `rule-check.log`, `diff-check.log`, `tabs.log`, `documents.log` |

The review also reproduced a separate strict IR mismatch on the
previous interpreter. When an alias names an enclosing variant, as in
`(Some(-Skip) as outer)`, its type narrows the payload but lowering
rebuilds it from the wider payload. An alias on the negative pattern
itself passes under strict checking. See `alias-baseline.log` and
`nested-alias-probes.log`. Follow-up item 5.20 covers the enclosing
alias and related pattern forms.

### Milestone 6.7 checks

The combined checks used `f9d190ef` with OCaml 5.4.0. Logs are
in `/private/tmp/smalllinks-met-5-20/`. Independent review checked
alternative fallthrough, linear bindings, native evaluation order,
quantified types and mixed handler operations. See
`independent-review.log`, `independent-working-review.log` and
`independent-working-edge.log`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make all-ci`, including a fresh Dune build directory | Passed with `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`. | `final-ci-build.log`, `final-clean-ci-build.log` |
| `make tests` | 1,226 passed across 42 suites. Two existing cases were ignored. All four scripts passed. | `all-tests.log` |
| `./test-harness tests/<suite>.tests` on affected suites | All passed, including 54 pattern, 51 record, 28 variant and 30 typed IR tests. | `default-<suite>.log` |
| Frontend rechecking and strict IR checks | Passed for handlers (153), effect annotations (76), collections (70), modules (58), records (51) and patterns (54). The strict handler REPL and example runner also passed. | `strict-<suite>.log`, `strict-repl.log`, `strict-examples.log` |
| `opam exec -- ./run-tests unit-tests` | All 105 passed. | `unit-tests.log` |
| Direct `./links -e` probes | All 24 cases passed with default settings and strict checking. These include `(Some(-Skip) as outer)`, annotated record rests, and linear payloads after fallthrough. | `final-direct-probes.log` |
| Guide and temporary installation | All 18 runnable guide blocks and four entry points passed. `dune install` from the fresh CI build and `./tests/check-install.sh` passed. The installed interpreter passed the enclosing alias, quantified rest and linear fallthrough probes. | `guide.log`, `install.log`, `install-check.log`, `installed-examples.log`, `installed-pattern-probes.log` |
| `make rule-check`, `git diff --check`, tabs and document links | Passed. An `rg` scan covered the tabs rule because GNU find was unavailable. | `rule-check.log`, `diff-check.log`, `tabs.log`, `documents.log` |

### Milestone 4 follow-up checks

The combined checks used `15849dea` with OCaml 5.4.0. Items 4.5–4.9
share one compiler commit because interface inference, clause checking
and branch results use the same handler types and regressions. Logs are
in `/private/tmp/smalllinks-met-4-follow-up/`.

Independent reviews covered interface scope under nested handlers and
curried functions, argument evidence and expected types, result hints
from aborting clauses, member quantifier scope, linear state and
absolute results. The regressions cover the fixes for the issues found
in review, including late constraints on branch results and rechecking
distinct annotations across clauses for one member.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` and `make all-ci` | Passed. | `build.log`, `ci-build.log` |
| `opam exec -- ./run-tests unit-tests` | 105 passed. | `unit.log` |
| `make tests` | 1,092 passed across 42 suites, with two existing ignored cases. All four scripts passed. | `all-regressions.log` |
| `./test-harness tests/<suite>.tests` | Passed for `handlers` (127), `effect_annotations` (61), `native` (73), `native_permissions` (13), `polymorphism` (66), `typecheck_examples` (34), `recheck_frontend_transformations` (3), `typed_ir` (30) and `modules` (49). | `<suite>.log` |
| `./test-harness` with frontend rechecking and strict IR checking | All 201 handler, effect annotation and native permission cases passed. | `strict-<suite>.log` |
| Handler and native specification examples with strict checking | 22 checks passed, including rejected examples and linear state variants. The handler example runner returned `() : ()`. | `spec-examples.log`, `strict-examples.log` |
| `./tests/repl_handlers.testscript` | Passed. | `repl.log` |
| `make rule-check` and `git diff --check` | Passed. GNU find was unavailable for the tabs rule. The same patterns passed with `rg`. | `rule-check.log`, `tabs.log`, `diff-check.log` |

### Milestone 3 follow-up checks

The combined checks used `d93cf72f` and OCaml 5.4.0. Logs are in
`/private/tmp/smalllinks-met-3-follow-up.iTO12K/`. Independent review
covered lock access, argument order, the value restriction, kind
checks and quantified record lowering. Review fixes preserved the type
of frozen arguments, the evaluation of the record base, and introduction
within an eligible handler clause.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` for the intermediate commits `77d1ffee` and `3557f45d`, and `make all-ci` for `d93cf72f` | Passed. | `77d1ffee-build.log`, `3557f45d-build.log`, `reviewed-ci-build.log` |
| `make tests` | 1,070 passed across 41 suites. Two existing pattern cases were ignored. All four scripts passed, covering the REPL, print and reparse, and example registration. | `reviewed-tests.log` |
| `./test-harness` on the affected suites listed under [Checks](#checks) | Passed. `handlers` passed 118, `effect_annotations` 61, `polymorphism` 66, `freezeml` 67, `records` 39, `typed_ir` 30 and `typecheck_examples` 34. | `reviewed-<suite>.log` |
| `opam exec -- ./run-tests unit-tests` | All 101 passed. | `reviewed-unit-tests.log` |
| Handler aggregate with frontend rechecking and strict IR checks | All nine assertions passed. | `reviewed-strict-handlers.log` |
| `./links -e`, file execution with an import and `--set=typecheck_only=true` | Passed. | `reviewed-entry-points.log` |
| `opam exec -- dune install --profile=ci --prefix="$prefix" links` and `tests/check-install.sh "$prefix/bin/linx"` | Passed. The installed interpreter also ran a modal handler and an explicitly polymorphic function outside the checkout. | `reviewed-install.log`, `reviewed-install-check.log`, `reviewed-install-examples.log` |
| `make rule-check`, `git diff --check`, the document check and the `rg` tab scan | Passed. The `rg` scan used the tabs rule's file patterns because GNU find was unavailable. | `reviewed-rule-check.log`, `reviewed-diff-check.log`, `reviewed-docs.log`, `verified-tabs.log` |

### Milestone 2 follow-up checks

Logs are in `/private/tmp/smalllinks-met-12.iA9tXw/`. The first checks
used the 2.6 compiler changes in `a566ff95` and OCaml 5.4.0.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` | Passed. | `make-2.6.log` |
| `./test-harness tests/modal_syntax.tests` and `./test-harness tests/roundtrippable_types.tests` | 33 and 9 passed. | `modal-syntax-2.6.log`, `2.6-roundtrippable_types.log` |
| `./test-harness` on `handlers`, `effect_annotations`, `polymorphism` and `typecheck_examples` | 118, 40, 56 and 34 passed. | `2.6-<suite>.log` |
| `tests/roundtrippable_types.testscript` from `010c0f87` | 12 passed. | `roundtrip-syntax-2.6.log` |
| `./links -e` on the quantified handler annotation, with frontend rechecking and strict IR checks | Returned `42 : Int`. | `2.6-strict-handler.log` |
| `opam exec -- menhir --table --dump --explain` on the old and new grammar | No conflicts in either grammar. | `/private/tmp/links-met-26-menhir.axHkzh/` |
| `make rule-check` | Passed. GNU find was unavailable for the tabs rule. The same file patterns passed with `rg`. | `2.6-rule-check.log`, `2.6-tabs.log` |
| `git diff --check` for the 2.6 files | Passed. | `2.6-diff-check.log` |

The combined checks used the compiler changes in `9b9a1e10` and OCaml
5.4.0. Independent review checked both printer paths, lexical scope
in annotation and function diagnostics, and REPL recovery after a
failed `@load` and `@withtype`. Review fixes made source name maps
lazy, displayed the original modalities in a mismatch, and resolved
the interface named in an arity error against the failing scope.

| Command or check | Result | Log |
| --- | --- | --- |
| `make all-ci` | Passed. | `2.7-ci-build.log` |
| `make tests` | 997 passed across 41 suites, with two existing ignored pattern tests. All four scripts passed. | `2.7-tests.log` |
| `./test-harness` on `handlers` and `effect_annotations` | 118 and 40 passed. | `2.7-handlers.log`, `2.7-effect_annotations.log` |
| `opam exec -- ./run-tests unit-tests` | All 101 passed. | `2.7-unit-tests.log` |
| Handler aggregate with frontend rechecking and strict IR checks | All nine assertions passed. | `2.7-strict-handler-examples.log` |
| `opam exec -- dune install --profile=ci --prefix="$prefix" links` and `tests/check-install.sh "$prefix/bin/linx"` | Passed. Installed `linx` also printed `[Effects.Reader]` on a function type outside the checkout. | `2.7-install.log`, `2.7-install-check.log` |
| `make rule-check`, `git diff --check` and the `rg` tabs check | Passed. GNU find was unavailable. | `2.7-rule-check.log`, `2.7-diff-check.log`, `2.7-tabs.log` |
| REPL `@load`, `@withtype` and scope review probes | Passed. | `/private/tmp/smalllinks-met-2.7-review.faExXe/` |

### Historical check records

The results below apply to their listed revisions and drafts.

The milestone 4 review draft passed `git diff --check`
against `98d39ac8`.

### Follow-up review checks

The combined documentation review used `25b07c25` with edits to the
four MET documents. The review distinguished past checks from pending
work, organised the implementation notes by plan item and added
function upcast arity checks. The user confirmed that comprehensions
must also work with empty or custom preludes that have no list helpers.

| Command or check | Result | Log |
| --- | --- | --- |
| `python3 /private/tmp/smalllinks-met-doc-review/check_docs.py` | Passed. Checked 114 local links, fenced blocks, table columns and tabs in the MET documents and the SmallLinks guide. | `/private/tmp/smalllinks-met-doc-review/documents.log` |
| `make rule-check` | Passed. GNU find was unavailable for the tabs rule on macOS. The document tab scan passed. | `/private/tmp/smalllinks-met-doc-review/rule-check.log` |
| `git diff --check` | Passed. | `/private/tmp/smalllinks-met-doc-review/diff-check.log` |
| Changed unary-arrow examples | Checked on the same compiler. | `/private/tmp/met-spec-unary-arrow.w445qi` |

At `25b07c25`, `./links --set=typecheck_only=true -e` accepted an
upcast from `Int -> Int` to `(Int, Int) -> Int`. Calling the
upcast function with `./links -e` failed with
`Invalid_argument("List.fold_right2")`, both by default and with
`--set=typecheck_ir=true --set=fail_on_ir_type_error=true`.
Items 3.11 and 5.7 track the fix. See
`/private/tmp/smalllinks-met-function-upcast.cNAgNr`.

The integration review draft at `a3e48a2d` passed `make rule-check`,
`git diff --check` and checks of the edited document links. GNU find
was unavailable, so an `rg` scan checked the edited files for tabs.
Probes with `./links -e` confirmed the existing rejection of `Foo`,
the incorrect rejection of a variant under `[]`, and the inconsistent
type of a call to a custom comparison. Logs are under
`/private/tmp/smalllinks-met-integration-review.TGt6f6/`.

The review used compiler revision `98d39ac8`. Logs are under
`/private/tmp/smalllinks-met-follow-up-review.CJ9Fkz/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `./links --set=show_quantifiers=true -e` on 12 examples | Confirmed behaviour at the tested revision. The signed recursive example returned `(42, true)`. Without the signature, the second call to `g` failed with `Expected Int, got Bool`. | `examples.log` |
| Document links and code fences, and `./links -e` on the recursive example from the specification | Passed. | `documents.log` |
| `make rule-check` | Passed. GNU find was unavailable for the tabs rule. The same file patterns passed with `rg`. | `rule-check.log`, `tabs.log` |
| `git diff --check` | Passed. | `diff-check.log` |

The recursive result and modal record examples were checked again at
`a18e3c67` with `./links --set=show_quantifiers=true -e`. Separate
calls to `f` used different types. Extending the open record outside
`Reader` succeeded with `r::Row(Abs)`. Direct extension with an absolute
presence failed, and explicitly converting the record first worked when
the presence variable was in scope. `hd([1,2])` and `tl([1,2])` returned
`1` and `[2]`. Document links, `make rule-check` with the same `rg` tabs
check, and `git diff --check` passed. Logs are under
`/private/tmp/smalllinks-met-list-review.Dwbgd0/`.

At `a18e3c67`, `./links -e` on the modal record example in SPEC.md
produced the expected type, and a handler supplied `42` to its `run`
callback. Further probes reproduced the discarded linear row tail,
the `Base` alias mismatch, the value restriction bypass, the
argument-order mismatch, the guarded `mu` rejection and the extra
quantifier from a signature hole. Logs are under
`/private/tmp/smalllinks-met-record-example.GMczGr/`.

### Milestone 3.12 checks

The checks used `fa9dd1e3` with the `Presence(Abs)` working-tree fix
and OCaml 5.4.0. Logs are under
`/private/tmp/smalllinks-met-presence-fix.rdEH3E/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk make` | Passed. | `build-sdk.log` |
| `./test-harness tests/<suite>.tests` for `records`, `effect_annotations`, `handlers`, `presence_type_arg`, `recheck_frontend_transformations` and `typed_ir` | 232 passed. The acceptance case ran with frontend rechecking, strict IR checks and optimisation. | `<suite>.log` |
| `./links -e` on modal record extensions and updates | Passed for absent and present absolute fields, a mixed record with a callback, and open rows in both contexts. The rejection checks produced the expected type errors. | `probes.log` |
| `make rule-check` and `git diff --check` | Passed. The tabs rule used `rg` with the same file patterns. | `rule-check.log`, `tabs.log`, `diff-check.log` |

At `a3e48a2d` with the working-tree test change,
`./test-harness tests/records.tests` passed all 35 tests with
`--optimise` off. Logs are under
`/private/tmp/smalllinks-met-default-checks.dWIhNT/`.

### Milestones 5–6 checks

The combined checks used `fcb1e97a` with OCaml 5.4.0. Logs are under
`/private/tmp/smalllinks-met-56/`. Independent reviews covered Fresco,
typed lowering and IR, and REPL recovery. That revision included the
review fixes, regression tests and matching prelude.

| Command or check | Result | Log |
| --- | --- | --- |
| `make`; `make all-ci`; `make all-ci` with a fresh Dune build directory | Passed. | `final-build.log`, `final-ci.log`, `final-clean-ci.log` |
| `opam exec -- ./run-tests unit-tests` | 101 passed. | `final-unit.log` |
| `./test-harness tests/<suite>.tests` for affected suites | Passed, including 118 handler, 40 effect annotation, 17 modal syntax, 56 polymorphism, 64 FreezeML, 26 typed IR and 34 example checks. | `final-focused.log`, `final-suite-<suite>.log` |
| `make tests` | 967 passed in 41 suites. Two existing redundant-pattern cases were ignored. Four scripts passed, including the REPL, example registration and 12 print-and-reparse cases. | `final-all.log` |
| `./links --set=recheck_frontend_transformations=true --set=typecheck_ir=true --set=fail_on_ir_type_error=true --optimise --path=examples/handlers examples/handlers/tests.links` | All nine aggregate assertions passed under strict checking and optimisation. | `final-strict-examples.log` |
| Run the SmallLinks guide programs, including the import, `-e`, typecheck-only and REPL examples | Passed. | `final-guide.log`, `guide/*.log` |
| `opam exec -- dune install --profile=ci --prefix="$prefix" links`, then `./tests/check-install.sh "$prefix/bin/linx"` and two installed modal programs | Passed outside the checkout, including a standard library import, an interface handler and mixed modal and quantified type application. | `final-install.log`, `final-install-prefix.txt` |
| `make rule-check` and `git diff --check 4fd5fba4..HEAD` | Passed. GNU find was unavailable for the tabs rule. The same file patterns passed with `rg`. | `final-source.log`, `final-tabs.log`, `final-whitespace.log` |

### Milestone 4 checks

The checks used `0a9eaaa9`. Logs are under
`/private/tmp/smalllinks-met-4/`. An independent review checked the
handler rules against the thesis and Fresco, and checked the retained
runtime fixtures. The source tests covered the fixes for rigid variables,
state scope, and modal result and argument inference.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` and `make all-ci` | Passed. | `build.log`, `ci-build.log` |
| `opam exec -- ./run-tests unit-tests` | All 101 passed, including 17 modal effect test groups. | `unit.log` |
| `./test-harness tests/handlers.tests` and `./test-harness tests/effect_annotations.tests` | 115 and 18 passed. | `handlers.log`, `effect_annotations.log` |
| `./test-harness tests/<suite>.tests` for `modal_syntax`, `native`, `polymorphism` and `typecheck_examples` | 16, 73, 56 and 35 passed. | `<suite>.log` |
| `make tests` | 937 passed in 41 suites, with two existing ignored cases. All four scripts passed. | `all-regressions.log` |
| `make rule-check` and `git diff --check aeb228c2..HEAD` | Passed. GNU find was unavailable for the tabs rule. The same file patterns passed with `rg`. | `rule-check.log`, `tabs.log`, `diff-check.log` |
| `opam exec -- dune install --profile=ci --prefix="$prefix" links` and `./tests/check-install.sh "$prefix/bin/linx"` | Passed on the row-based native entry points. | `install.log`, `install-check.log` |

### Milestone 3 checks

The combined checks used `33b15eaa`. Logs are under
`/private/tmp/smalllinks-met-3/`. Independent reviews covered the
type solver, lock and modal checking, polymorphic application and
generalisation, pattern typing and the range helper. The regression
tests covered the fixes found in review.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` and `make all-ci` | Passed. | `build.log`, `ci-build.log` |
| `opam exec -- ./run-tests unit-tests` | All 84 passed. Source checks cover accepted and rejected higher-rank, modal, data-row, presence and linear cases. | `unit.log` |
| `./test-harness tests/handlers.tests` and `./test-harness tests/effect_annotations.tests` | 115 and 18 passed. The other affected suites passed separately, including the two new range tests in `native`. | `handlers.log`, `effect_annotations.log`, `<suite>.log` |
| `make tests` | 937 passed in 41 suites, with two existing ignored cases. All four scripts passed. | `all-regressions.log` |
| `./links -e '40 + 2'` and `./links --path=examples/handlers examples/handlers/tests.links` | Returned `42 : Int` and `() : ()`. | `expression.log`, `import.log` |
| `./tests/repl_handlers.testscript` and `./links --set=typecheck_only=true examples/extensible-case.links` | Passed. | `repl.log`, `typecheck.log` |
| `make rule-check` and `git diff --check ea12bfed..33b15eaa` | Passed. GNU find was unavailable for the tabs rule. The same file patterns passed with `rg`. | `rule-check.log`, `tabs.log`, `diff-check.log` |
| `opam exec -- dune install --profile=ci --prefix="$prefix" links` and `./tests/check-install.sh "$prefix/bin/linx"` | Passed. | `install.log`, `install-check.log` |

### Milestone 2 checks

The combined checks used `9de77c76`. Logs are under
`/private/tmp/smalllinks-met-1-2.WacKXl/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` and `make all-ci` | Passed. | `final-dev-build.log`, `final-ci-build.log` |
| `make tests` | 935 passed across 41 suites, with two existing ignored pattern tests. All four scripts passed. | `final-tests.log` |
| `./test-harness tests/handlers.tests` and `./test-harness tests/effect_annotations.tests` | 115 and 18 passed. Other affected suites passed separately. | `final-handlers.log`, `final-effect_annotations.log`, `final-<suite>.log` |
| `opam exec -- ./run-tests unit-tests` | All 60 passed, including scoped contexts, modality algebra, kinds, registry lookup and modal print-and-reparse in both engines. | `final-ir.log` |
| `make rule-check` and `git diff --check bcf3816c..9de77c76` | Passed. GNU find was unavailable for the tabs rule. The same file patterns passed with `rg`. | `final-rules.log`, `final-tabs.log`, `final-diff-check.log` |
| `opam exec -- dune install --profile=ci --prefix="$prefix" links` and `./tests/check-install.sh "$prefix/bin/linx"` | Passed. Installed `linx` ran the list and import checks and accepted a qualified modal declaration. | `final-install.log`, `final-install-check.log` |
| `./links` on the two updated guide examples | Returned `2` and `(true, false)`. | `final-guide.log` |

The 2.1 and 2.2 commits also built and passed focused tests on their
own. Their logs are under `/private/tmp/smalllinks-met-2-1.HYwjYW/`.

### Implementation baseline

Checks used `21348680` with OCaml 5.4.0 and Dune 3.20.2. Logs are under
`/private/tmp/smalllinks-met-1-2.WacKXl/`. The handler baseline suite
included the eight new cases in 1.4.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` | Passed. | `baseline-build.log` |
| `make tests` | 928 cases across 40 suites and all three scripts passed. | `baseline-tests.log` |
| `opam exec -- ./run-tests unit-tests` | 44 passed. | `baseline-ir.log` |
| `./links -e '40 + 2'` | Returned `42 : Int`. | `baseline-expression.log` |
| `./links examples/handlers/tests.links` | The imported handler examples passed. | `baseline-import.log` |
| `./tests/repl_handlers.testscript` | The definition and call passed. | `baseline-repl.log` |
| `./links --set=typecheck_only=true examples/extensible-case.links` | Passed. | `baseline-typecheck.log` |
| `./test-harness tests/handlers.tests` with the eight new cases | 115 passed. | `/private/tmp/small-met-handler-baseline.log` |

The individual suite logs use the `baseline-<suite>.log` names.
The eight handler cases covered runtime scope, forwarding, resumption,
state evaluation order and linear bindings. Milestones 3 and 4 added
modal typing checks after this baseline.

### Design approval and `unsafe_cast` removal

Checks used `a557219f` with the approved design and removal changes.
Logs are under `/private/tmp/smalllinks-unsafe-cast.QOdUZ6/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` | Passed. | `build.log` |
| `./links -e 'unsafe_cast(42)'` | Rejected with `Unknown variable unsafe_cast.` | `removed.log` |
| `./test-harness tests/native.tests` | 71 passed, including the removal regression. | `native.log` |
| `./test-harness tests/handlers.tests` | 107 passed. | `handlers.log` |
| `./test-harness tests/effect_annotations.tests` | 18 passed. | `effect-annotations.log` |
| `./test-harness tests/typecheck_examples.tests` | 35 passed. | `typecheck-examples.log` |
| `./links examples/extensible-case.links` | Returned `("A", "B", "C")`. | `extensible-case.log` |
| `make rule-check` | Passed. GNU find was unavailable for the tabs rule. The same file patterns passed with `rg`. | `rule-check.log`, `tabs.log` |
| `git diff --check` | Passed. | `diff-check.log` |

### Initial design checks

The initial draft received separate read-only reviews against the thesis,
Fresco sources and SmallLinks implementation. The draft incorporated
corrections to locks, generalisation, kind restrictions, syntax and
native effects.

Checks on 14 November 2026 used
`e117db9da0bca9f45e9a12d2c3df808ec3880a6e` plus the initial draft.
Logs and extracted snippets are under
`/private/tmp/smalllinks-met-design.EcMuxo/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` | Passed on the unchanged compiler source. | `build.log` |
| `make rule-check` | Passed. GNU find was unavailable for the tabs rule; the same file patterns passed with `rg`. | `rule-check.log`, `tabs.log` |
| `git diff --check` and `git diff --no-index --check /dev/null` for each new document | No whitespace diagnostics. | `diff-check.log`, `documents.log` |
| Check local document links, source-reference paths, code fences and document whitespace | Passed. | `documents.log` |

### Initial draft examples run with the baseline compiler

During the initial drafting, all 20 fenced Links snippets were extracted
from SPEC.md into temporary files, with preceding definitions supplied
where needed. These files preserve the examples before the subsequent
syntax changes and deferral of `escape`. They were checked with
`./links --set=typecheck_only=true` using
the row-based compiler at the revision above. The accepted
snippets were then run with `./links`.

| Snippets | Result and cause | Log |
| --- | --- | --- |
| Seven using supported syntax | Accepted and returned the documented values: `(42, true)`, `42`, `1`, `42`, `[1, 2]`, `42`, `42`. | `example-02.log`, `example-03.log`, `example-08.log`, `example-12.log`, `example-14.log` through `example-16.log` |
| One deliberately ill-typed example | Rejected as intended: `do Ask + 1` requires an `Int` result, while the handler resumes with `true`, requiring `Bool`. | `example-09.log` |
| Twelve using proposed modal syntax | The baseline parser rejected unsupported forms such as `[Ask:() => Int]` and `a::Abs`. | `example-01.log`, `example-04.log` through `example-07.log`, `example-10.log`, `example-11.log`, `example-13.log`, `example-17.log` through `example-20.log` |

`examples.json` lists every command result. The implementation baseline,
modal acceptance tests and combined checks are recorded in the
earlier sections of this plan.

### Initial design follow-up checks

These checks used the same source revision and existing baseline
executable, with the revised documents. Logs are under
`/private/tmp/smalllinks-met-review2-w4r6hp65/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `./links` on runtime counterparts of the revised conditional, native-call, list and variant examples, using baseline type annotations | All four passed: `42`, printed `hello` and returned `()`, `[20, 22]`, and `42`. | `runtime-checks.json`, `conditional.log`, `native.log`, `list.log`, `variant.log` |
| `./links --set=typecheck_only=true` on the variant payload mismatch using the baseline variant syntax | Rejected as expected: `Just(true)` cannot have an `Int` payload. | `variant-rejection.log` |
| `./links -e` with a replacement `intRange` that prints before returning `[42]`, followed by `[1..3]` | Printed `shadowed[42] : [Int]`. This reproduced the helper-lookup issue addressed in 3.2. | `range-shadowing.log` |
| Check document links, code fences, table columns and whitespace; `git diff --check` | Passed. | `documents.log`, `diff-check.log` |

### Effect-interface review checks

R1–R6 decisions and the converted examples were reviewed against the
thesis and Fresco sources. The checks used
`e117db9da0bca9f45e9a12d2c3df808ec3880a6e` and the updated documents.
Logs are under `/private/tmp/smalllinks-met-decisions-6z_udikx/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `./links` on the two new accepted handler bodies in example 15, without the proposed interface declarations | Both returned `42 : Int`. | `mixed-interfaces.log`, `explicit-forwarding.log` |
| Check document links, reference paths, code fences, table columns and whitespace | Passed. | `documents.log` |
| Check that modal contexts use interface names, and inspect the changes from the previous draft | Passed. | `documents.log`, `SPEC.md.diff`, `PLAN.md.diff` |
| `git diff --check` | Passed. | `diff-check.log` |

Milestones 2–4 later checked interface declarations, their typing
rules and the rejection of incomplete handlers.

### R7 syntax checks

These checks used `e117db9da0bca9f45e9a12d2c3df808ec3880a6e` and
the revised documents. Logs are under
`/private/tmp/smalllinks-met-r7-i0m_lbp4/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `./links` on the annotated variant example with the baseline compiler's delimiters | Returned `42 : Int`. | `variant.log` |
| `./links --set=typecheck_only=true` on its `Just(true)` variant | Rejected as expected because the declared payload is `Int`. | `variant-payload-rejection.log` |
| Check the proposed delimiters against the existing variant-row grammar; check document links, fences, tables and whitespace | Passed. Milestone 2 later implemented the new delimiters and reserved `List` rule. | `documents.log` |
| `git diff --check` | Passed. | `diff-check.log` |
