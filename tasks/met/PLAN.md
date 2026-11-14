# SmallLinks modal effect types plan

The language design and scope are in [SPEC.md](SPEC.md#scope).
This plan records milestones, dependencies, progress and checks.
[IMPL.md](IMPL.md) will record significant implementation decisions.

Work stays on `small-met`. The first implementation is complete.
The follow-up items below are pending review before implementation.

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
- [ ] **2.6** Enforce the reviewed surface syntax. Restrict `=>` to
  interface member signatures and handler clause annotations. Reject
  nested list and modal element types without parentheses, and migrate
  any affected source or printer output. Test both unary arrow forms,
  `List A` and `List(A)`, the reserved `effect` keyword and the rejection
  of empty interfaces.
- [ ] **2.7** Check that sequential interface declarations and repeated
  imports follow the same scope as `typename`. Preserve the identities
  of earlier references and the existing rule against duplicate operation
  names. Test shadowing and reopening modules and repeated imports in one
  input and across REPL inputs. Make type printers choose a name that
  resolves to the right declaration when one is in scope. Mark
  interfaces with no visible name as out of scope and distinguish
  shadowed identities in diagnostics. Verify the resolved identities
  in print-and-reparse checks.

Completion check: the migrated list and variant syntax and the modal
type representation have focused checks. Record, variant and presence
behaviour remains covered, and `escape` is identified as deferred.
Printed annotations preserve the identity of interfaces that can be
named in the current scope.

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
- [ ] **3.5** Fix recursive `Abs` checks so they follow the types of the
  fields and respect enclosing modalities. Use the same field requirements
  when checking and narrowing kinds. Test absolute and ambient callback
  fields, including a recursive reference whose arguments change.
  Accept guarded explicit `mu` types under modalities and still reject
  unguarded recursion.
- [ ] **3.6** Reject types with a non-identity modality at `Base`.
  Test direct and indirect uses through aliases at `Base`, `Mono` and
  `MonoAbs`. Retain the existing checks on primitive types, row tails
  and field presences.
- [ ] **3.7** Require explicit universal binders in source signatures.
  Test type, row and presence variables, holes, leading modalities and
  lexical references through nested `forall`. Update the default and
  FreezeML preludes, standard library, active examples and fixtures in
  the same commit.
- [ ] **3.8** Apply Maetel's variable access rule before
  instantiation. Use consecutive leading modalities for the residual.
  Test access at a still-bound quantifier, absolute access, and explicit
  type application on both sides of a lock. Make grouped frozen variables
  behave like `~x`.
- [ ] **3.9** Use all available partial type information before fixing
  polymorphic or modal instantiation. Test argument order, curried
  applications and modal pattern binders. Keep modality conversion
  independent of constraint order and ask for an annotation when the
  available constraints leave a choice.
- [ ] **3.10** Check the value restriction on every path that introduces
  a quantifier or modality. Cover effectful computations, failing binding
  patterns, and computations that return an already-polymorphic or modal
  value. Check that annotation variables cannot escape.
- [ ] **3.11** Preserve known quantifiers during record projection and
  extension, and preserve expected element types in list comprehensions.
  Require a discarded record tail in an upcast to be unrestricted.
  Run the corresponding lowering checks in 5.7.
- [x] **3.12** Preserve a field with `Presence(Abs)` when extending a
  [closed modal record](SPEC.md#modal-record-extension). Cover a field
  that is absent or present, a presence without an `Abs` bound and a
  record whose type must be instantiated first. The general interaction
  with row and presence variables is
  [future work](SPEC.md#modal-types-and-data-rows).

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
- [ ] **4.5** Fix inference of shared interface arguments. Use known
  types from handled expressions and clauses before choosing an
  instance. Check that reordering equally valid constraints produces
  the same type or the same request for an annotation. Cover known
  types in branches, local value bindings and local function bodies.
- [ ] **4.6** Use return and operation clauses when inferring the
  handler's result. Retain known modal types from aborting clauses
  and pass expected type information through return bindings. Test
  default and explicit returns, including a return through a local
  binding, as well as handlers used as application arguments.
- [ ] **4.7** Check that member quantifiers cannot escape into an
  outer type or a shared source annotation. Allow a flexible type
  variable that is used only within one operation clause to be
  solved there. Test both uses of the same annotation syntax.
- [ ] **4.8** Apply the reviewed handler usage rules. Check a captured
  linear value in all shallow clauses as alternatives. Require each
  deep clause to use its [linear state](SPEC.md#linear-state) once on
  each branch. Test one, zero and two uses, including the implicit
  return, state binder shadowing and passing linear state to a
  resumption. Check replay through an enclosing handler and sequential
  state initialisation.
- [ ] **4.9** Use the same rule for relative prefixes on absolute
  results in `if`, `switch` and handlers. Test matching underlying
  types, conflicting underlying types and results that still depend
  on their context.
- [ ] **4.10** Keep effectful `crypt` calls when their result is unused.
  Test the optimised code and a run without optimisation. Check the
  reviewed `wild` signatures for `show`, `parseDate` and `sleep`,
  the pure `error` signature, and the existing `exit` signature.

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
- [ ] **5.5** Keep resolved interface signatures available in local modules
  and carry interface and operation names with the exported values and
  types of a prelude or a non-isolated input. Check that dependency loading
  recognises local modules in the same scopes as ordinary declarations.
  Test local module handlers and their scope, a custom prelude,
  successive inputs with both isolation settings, and REPL imports
  and failed loads.
- [ ] **5.7** Preserve the checked types during lowering of quantified
  record operations and comprehensions. Run the regressions from 3.11
  through ordinary execution, typed frontend rechecking and strict IR
  checking. Include a list with modal elements.
- [ ] **5.8** Support [linear lists](SPEC.md#list-linearity). Update list
  kinds, inference, pattern lowering and primitive types together.
  Check that cons and append preserve all the elements and that list
  patterns split each list once on a matching path. Keep the
  unrestricted bounds on consumers and comprehension helpers that
  depend on them. Test empty and non-empty lists, nested patterns and
  whole-list fallbacks. Reject duplication, discards and calls to `hd`
  or `tl` on a linear list, including with explicit type application.
  Run the accepted examples with typed frontend rechecking, strict IR
  checks and optimisation.

The [lambda evaluator](MIGRATION.md#installed-examples) stays deferred
for this version. The design records [modality-parameterised
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
- [ ] **6.4** After the follow-up changes in 2–5, update the
  SmallLinks guide, including the signatures, lock access and linear lists.
  Review the combined changes and run the affected checks below.
  Record the new tested revision and log paths.

Completion check: a clean CI build and temporary installation work, all
in-scope regressions and unit tests pass, printed types can be reused as
annotations, the guide matches the compiler, and deferred features have
an explicit inventory.

## Checks

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
   `roundtrippable_types` and `typecheck_examples`. Migrate the behaviour
   checks in `effectname` to interface declarations before retiring the
   old syntax tests.
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

Milestone 3.12 is implemented and checked. The other follow-up work in
milestones 2, 3, 5 and 6 is pending user review.
The [implementation notes](IMPL.md#follow-up-review) give the cases and
source locations for the review.

The milestone 4 review settled the handler usage and branch result
rules. The fixes in items 4.5–4.10 are pending. Run the affected
handler, effect annotation and native suites with typed frontend
rechecking and optimisation, followed by the combined milestone 6
checks. The milestone 4 review draft passed `git diff --check`
against `98d39ac8`.

### Follow-up review checks

The review used compiler revision `98d39ac8`. Logs are under
`/private/tmp/smalllinks-met-follow-up-review.CJ9Fkz/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `./links --set=show_quantifiers=true -e` on 12 examples | Confirmed current behaviour. The signed recursive example returned `(42, true)`. Without the signature, the second call to `g` failed with `Expected Int, got Bool`. | `examples.log` |
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
| `./test-harness tests/<suite>.tests` for `records`, `effect_annotations`, `handlers`, `presence_type_arg`, `recheck_frontend_transformations` and `typed_ir` | 232 passed. The new acceptance case runs with frontend rechecking, strict IR checks and optimisation. | `<suite>.log` |
| `./links -e` on modal record extensions and updates | Passed for absent and present absolute fields, a mixed record with a callback, and open rows in both contexts. The rejection checks produced the expected type errors. | `probes.log` |
| `make rule-check` and `git diff --check` | Passed. The tabs rule used `rg` with the same file patterns. | `rule-check.log`, `tabs.log`, `diff-check.log` |

### Milestones 5–6 checks

The combined checks used `fcb1e97a` with OCaml 5.4.0. Logs are under
`/private/tmp/smalllinks-met-56/`. Independent reviews covered Fresco,
typed lowering and IR, and REPL recovery. The review fixes and
regressions are included in that revision. The compiler switch and its
library and fixture changes share one commit so the revision builds
and runs with the matching prelude and tests.

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
runtime fixtures. Source tests cover the fixes for rigid variables,
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
tests include the fixes found in review.

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
`/private/tmp/smalllinks-met-1-2.WacKXl/`. The handler baseline suite includes the
eight new cases in 1.4.

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
The new handler cases cover runtime scope, forwarding, resumption,
state evaluation order and linear bindings. The modal typing checks
remain in [milestones 3 and 4](#3-implement-modal-inference-and-polymorphism).

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
Fresco sources and SmallLinks implementation. Corrections to locks,
generalisation, kind restrictions, syntax and native effects are
included.

Checks on 14 November 2026 used
`e117db9da0bca9f45e9a12d2c3df808ec3880a6e` plus these documents.
Logs and extracted snippets are under
`/private/tmp/smalllinks-met-design.EcMuxo/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` | Passed on the unchanged compiler source. | `build.log` |
| `make rule-check` | Passed. GNU find was unavailable for the tabs rule; the same file patterns passed with `rg`. | `rule-check.log`, `tabs.log` |
| `git diff --check` and `git diff --no-index --check /dev/null` for each new document | No whitespace diagnostics. | `diff-check.log`, `documents.log` |
| Check local document links, source-reference paths, code fences and document whitespace | Passed. | `documents.log` |

### Initial draft examples run with the current compiler

During the initial drafting, all 20 fenced Links snippets were extracted
from SPEC.md into temporary files, with preceding definitions supplied
where needed. These files preserve the examples before the subsequent
syntax changes and deferral of `escape`. They were checked with
`./links --set=typecheck_only=true` using
the existing row-based compiler at the revision above. The accepted
snippets were then run with `./links`.

| Snippets | Result and cause | Log |
| --- | --- | --- |
| Seven using supported syntax | Accepted and returned the documented values: `(42, true)`, `42`, `1`, `42`, `[1, 2]`, `42`, `42`. | `example-02.log`, `example-03.log`, `example-08.log`, `example-12.log`, `example-14.log` through `example-16.log` |
| One deliberately ill-typed example | Rejected as intended: `do Ask + 1` requires an `Int` result, while the handler resumes with `true`, requiring `Bool`. | `example-09.log` |
| Twelve using proposed modal syntax | The current parser rejected unsupported forms such as `[Ask:() => Int]` and `a::Abs`. Modal checking for these examples is pending implementation. | `example-01.log`, `example-04.log` through `example-07.log`, `example-10.log`, `example-11.log`, `example-13.log`, `example-17.log` through `example-20.log` |

`examples.json` lists every command result. The parse errors came from
passing the proposed syntax to the current compiler. Modal acceptance
tests will be added in milestones 3–6.

The full implementation baseline in 1.3, modal acceptance tests and
final combined checks remain pending.

### Follow-up checks

These checks used the same source revision and existing baseline
executable, with the revised documents. Logs are under
`/private/tmp/smalllinks-met-review2-w4r6hp65/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `./links` on runtime counterparts of the revised conditional, native-call, list and variant examples, using current type annotations | All four passed: `42`, printed `hello` and returned `()`, `[20, 22]`, and `42`. The proposed type syntax remains pending implementation. | `runtime-checks.json`, `conditional.log`, `native.log`, `list.log`, `variant.log` |
| `./links --set=typecheck_only=true` on the variant payload mismatch using the current variant syntax | Rejected as expected: `Just(true)` cannot have an `Int` payload. | `variant-rejection.log` |
| `./links -e` with a replacement `intRange` that prints before returning `[42]`, followed by `[1..3]` | Printed `shadowed[42] : [Int]`. This confirms the helper-lookup issue in [Value restriction](SPEC.md#value-restriction). | `range-shadowing.log` |
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

Interface declarations, their type checks and incomplete-interface
rejections remain implementation checks for milestones 2–4.

### R7 syntax checks

These checks used `e117db9da0bca9f45e9a12d2c3df808ec3880a6e` and
the revised documents. Logs are under
`/private/tmp/smalllinks-met-r7-i0m_lbp4/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `./links` on the annotated variant example with the current compiler's delimiters | Returned `42 : Int`. | `variant.log` |
| `./links --set=typecheck_only=true` on its `Just(true)` variant | Rejected as expected because the declared payload is `Int`. | `variant-payload-rejection.log` |
| Check the proposed delimiters against the existing variant-row grammar; check document links, fences, tables and whitespace | Passed. The new delimiters and reserved `List` rule await compiler implementation. | `documents.log` |
| `git diff --check` | Passed. | `diff-check.log` |
