# Modal effects in Links

## Goal and scope

Implement modal effect types in Links on the `modal-effects` branch,
with two required outcomes:

1. Add syntax and typing for modal effect types. Represent effects
   using scoped rows of named effects grouping operations, including
   repeated effect labels and their ordering.
   Remove presence types from effect tracking. Retain the existing
   rows and presence types for records and variants.
2. Refactor Links' type inference engine to follow Fresco, including
   its support for first-class polymorphism and the extension to
   first-class modal types.

Use Wenhao's thesis and Aghilas' combined Met/Fresco implementation
as the main references. Start with Met and implicit ambient effects;
defer explicit effect variables from Met(X). Replace existing Links
effect annotations and migrate the affected examples and tests.
Defer the term-level mask operator, including its syntax, typing,
runtime support, and tests.

The implementation should accept and reject programs according to
the chosen rules and run accepted examples with their expected results.

Database support, control-flow linearity, and session failure are out
of scope for now. Follow `AGENTS.md` for repository conventions and
build and test commands.

## Current status

Environment preparation is complete. The two implementation goals
and the scope above were agreed on 6 November 2026. An initial source
comparison now records the selected rules, syntax, Links integration,
reference defects, and dependency-ordered changes D1--D8 in the design
document. Independent design review is complete and its four findings
are resolved. D1's scoped row and modality modules are implemented,
integrated, tested, and independently reviewed. D2a's modal quantifier
metadata and D2b's contextual arrows/modal type constructors are also
integrated, tested, and independently reviewed. D3a preserves modal
kinds on declaration parameters. D3b adds modal type and binder syntax,
implicit arrows, and temporary legacy normalisation. D3c adds effect
declarations, qualified operations, handler annotations, and freezing
syntax. D3d adds effect resolution and declaration/handler checks,
with independent review and all selected checks complete.
D4a adds non-mutating type inspection and modal kind classification,
also reviewed and tested. D4b adds separate well-formedness checks for
types, effect applications and signatures. Fresco inference and migration
remain incomplete. D4c adds persistent contexts and checked assignment,
with review and selected checks complete.

A read-only declaration investigation identified the module
name-resolution changes and affected pattern-matching handlers. A
second investigation confirmed a reference modal-kind defect for nested
and recursive datatype applications; the design records the correction
and required D4 tests.

Baseline checked on 5 November 2026 at commit `7100e289`:

| Check | Result |
|---|---|
| Compiler | OCaml 5.4.0 in the `default` opam switch |
| Build | `make no-db` passed |
| Handler tests | `tests/handlers.tests`: 95 passed |
| Effect syntax tests | `tests/effect_sugar.tests`: 44 passed |
| OCaml unit tests | `nodb-unit-tests`: 44 passed |

These results precede modal-effects implementation changes.

## Design

Sources, design questions, typing rules, examples, and technical
decisions belong in
[doc/modal-effects-design.md](doc/modal-effects-design.md).
Keep implementation progress and verification results in this plan.

Follow Aghilas' combined implementation for unresolved language
choices and record the decision. Check apparent implementation defects
against the thesis rules and small examples. Resolve routine code
organisation within the agreed design.

## Milestones

### 1. Rules, syntax, and migration design

Compare the thesis' Met calculus, Fresco algorithm, and modal inference
extension with Aghilas' combined implementation. Trace the affected
Links syntax, traversals, type checker, desugaring, intermediate
representation, interpreter, and JavaScript backend.

Specify absolute and relative modal types, ambient effect contexts,
context locks, operation invocation, handlers, and freezing.
Propose Links syntax using the reference notation `[E] A`, `<D> A`,
and `<L | D> A`, checking conflicts with the existing grammar.
Specify declarations for named effects grouping operations, following
Aghilas' combined implementation.

Define scoped row lookup, extension, removal, equality, and subeffecting.
Preserve repeated labels and the order of occurrences of the same
label. Keep record and variant row handling separate.

Map Fresco's judgements to Links modules and identify reusable code.
Specify the treatment of recursive bindings, records, variants, type
aliases, patterns, and built-in operations. Inventory old effect
annotations in the prelude, libraries, examples, and selected tests,
and record how they will migrate.

Complete when remaining language choices are resolved and the design
document maps the required rules to implementation tasks. Include
accepted and rejected examples for scoped rows, modal types, and
Fresco polymorphism, with expected types, results, or errors.

### 2. Modal syntax and scoped effect rows

Add modal types and the agreed term syntax to the lexer, parser,
syntax types, traversals, and type printer. Introduce a scoped effect
row representation and the operations specified in milestone 1.
Update affected type representations and interfaces, keeping record
and variant presence types intact.

Cover repeated labels, exchange of distinct labels, removal of one
occurrence, and relative modality composition. Check parsing and
printing, including invalid annotations.

Complete when the compiler builds and the syntax and scoped row
checks pass. Track remaining uses of the old effect representation
until their replacement is complete.

### 3. Fresco inference

Implement Fresco's algorithmic contexts, unknown type variables,
skeletons, ghosts, freezing, consistency, subtyping, constraint
collection, and solving. Connect type inference and skeleton inference
to Links terms, replacing the affected unification, generalisation,
and instantiation paths.

Adapt representative acceptance and rejection tests from the
reference implementation's `tests/fresco/`. Cover higher-rank and
polymorphic instantiation, information flow between functions and
arguments, freezing, and let generalisation. Extend the implementation
to the Links constructs identified in milestone 1.

Complete when the selected Fresco tests have their expected outcomes
and Links uses Fresco inference for the implemented constructs.
Document each difference from the thesis and reference implementation.

### 4. Modal inference and first working example

Extend Fresco inference with ambient effect contexts, locks, absolute
and relative modalities, implicit modal introduction and elimination,
and instantiation with modal types. Implement the chosen operation
and handler rules over scoped rows.

Connect elaboration to Links' intermediate representation and runtime.
Run a small program that invokes and handles an operation, together
with a rejected program that exercises modal variable access. Add
examples combining polymorphism and modal types, and nested handlers
with repeated effect labels.

Complete when accepted examples have the expected types and results,
rejected examples fail for the intended reasons, and affected tests
pass. Verify that dynamic handler selection agrees with
scoped row typing.

### 5. Links integration and migration

Finish the inference refactor across the in-scope Links constructs.
Migrate built-in type declarations, the prelude, affected libraries,
examples, and regression tests to modal syntax and typing. Update
desugaring, intermediate representation checks, and backends as needed.
Check both interpreter and JavaScript handling of the changed constructs.

Complete when the selected Links suites pass, expected changes in
accepted programs are recorded, and in-scope effect tracking uses
scoped rows throughout. Check that record and variant typing remains
supported with its existing row representation.

### 6. Documentation and review

Document the implemented syntax, inference behaviour, required
annotations, and migration from old effect annotations. Add runnable
examples and review the implementation against the source rules.

Complete when the agreed examples and relevant existing suites pass,
and a review against the chosen typing rules has resolved outstanding
implementation defects. Record completed behaviour and deferred work.

## Progress

- [x] Prepare the OCaml environment and build Links.
- [x] Run the initial handler, effect syntax, and OCaml unit tests.
- [x] Add the implementation plan and design document.
- [x] Record the modal syntax, scoped effect row, and Fresco goals.
- [x] Confirm effect-only row changes, annotation migration, and
  deferral of explicit effect variables.
- [x] Confirm named effects grouping operations as scoped row entries.
- [x] Defer the term-level mask operator.
- [x] Identify the main thesis sections and reference implementation files.
- [x] Compare source rules, probe reference behaviour, and record
  language choices and implementation dependencies.
- [x] Complete independent design review and resolve findings.
- [x] D1: implement and review scoped row and modality operations.
- [x] D2a: preserve modal quantifier kinds through shared type operations.
- [x] D2b: add contextual arrows/modal types and shared type operations.
- [x] D3a: preserve modal kinds on declaration parameters.
- [x] D3b: add modal type/binder syntax and temporary legacy normalisation.
- [x] D3c: add declaration, qualified operation, handler, and freezing syntax.
- [x] D3d: resolve effects/operations and check declarations and handler groups.
- [x] D4a: add non-mutating type reads and recursive modal kind classification.
- [x] D4b: check type/effect well-formedness and operation signatures.
- [x] D4c: add persistent contexts and checked type/row/presence assignment.
- [ ] Implement and test modal syntax and scoped effect rows.
- [ ] Refactor type inference to follow Fresco.
- [ ] Implement modal inference and run the first working example.
- [ ] Complete Links integration and migrate affected programs.
- [ ] Complete integration tests, documentation, and review.

## Working procedure

- Start each implementation task by reading `AGENTS.md`, this plan,
  the design document, and the relevant source files. The main agent
  owns design, integration, verification, progress records, and commits.
- Use fresh Sol 6.1 High subagents for simple tasks and Astra High
  subagents for harder investigations, changes, and reviews. Reserve
  extra-high effort for very difficult tasks. Give each
  agent its allowed files, sources, completion conditions, and checks.
  Use `.worktrees/<name>` for separate work. Run independent
  investigations and reviews in parallel, with one agent editing
  compiler code at a time. Review and integrate changes before
  dependent work begins.
- Give each task a concrete expected behaviour and completion check.
  Build and run the affected tests using the commands in `AGENTS.md`.
- Review expected types and rejection cases against the agreed rules.
  Record any intended changes to existing test expectations.
- Keep each change small enough to review and leave the compiler
  building. Independently review substantial changes and resolve the
  findings. Inspect the combined diff and commit each completed change
  with its tests and progress records, preserving unrelated changes.
- After each task, update progress, decisions, test results, remaining
  problems, and the next action here. Record the commit when available.
- Mark a task complete only when its stated checks pass. For partial
  work, state what works and what remains. Record failures with the
  failing command and a short description.

For compiler changes, run `make no-db` before the affected regression
suites. Start with `tests/handlers.tests` and `tests/effect_sugar.tests`;
include `tests/polymorphism.tests` and `tests/typecheck_examples.tests`
for the inference refactor. Run each suite separately and preserve
its feature settings. Run `opam exec -- ./run-tests nodb-unit-tests`
when changing covered code, then `make rule-check` and `git diff --check`.
Add acceptance and rejection tests for each changed typing behaviour.

## Decisions

- 5 November 2026: Work on `modal-effects`; database support,
  control-flow linearity, and session failure remain outside scope,
  as requested by the user.
- 6 November 2026: Modal syntax, scoped effect rows without presence
  types, and Fresco inference are required outcomes. The thesis and
  combined Met/Fresco implementation are the main references.
- 6 November 2026: Retain existing record and variant rows. Replace
  old effect annotations and migrate examples. Implement Met with
  Fresco first; defer explicit effect variables from Met(X).
- 6 November 2026: Use named effects grouping operations as scoped
  row entries, following Aghilas' combined implementation, as
  confirmed by the user.
- 6 November 2026: Defer the term-level mask operator, as requested
  by the user. Scoped row removal and relative modality composition
  remain part of the implementation.
- 6 November 2026: Qualify operations by their owning effect, using
  `State.Get` and `M.State.Get`, as confirmed by the user. Reject
  ambiguous unqualified operation names.
- 6 November 2026: An annotated handler resolves unqualified operation
  clauses against its selected effect, as confirmed by the user.
- 6 November 2026: Follow Aghilas for unresolved language choices.
  Include its higher-order effects with restricted exchange, fixed
  modal kinds, monomorphic lets, and signed recursion. Use a `modal`
  syntax prefix and `freeze(e)` to avoid Links XML/list/page conflicts.
  Require complete handler groups and correct repeated-row consistency.
  Details and the source comparison are in the design document.

## Design comparison and baseline

6 November 2026: Two read-only investigations compared reference rules
and Links integration in separate worktrees. Recorded syntax, source
rules, expected examples, migration requirements, and D1--D8.
Independent review identified four issues: weakening in subeffecting,
the equality solver's duplicate-row defect, shallow resumption typing,
and process type parameters. All four are resolved in the design.
Added `.worktrees/` to ignored local files.

Rechecked the unchanged compiler baseline:

| Check | Result |
|---|---|
| `make no-db` | Passed |
| `tests/handlers.tests` | 95 passed |
| `tests/effect_sugar.tests` | 44 passed |
| `tests/polymorphism.tests` | 54 passed |
| `tests/typecheck_examples.tests` | 167 passed, 15 ignored by existing settings |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed |
| Reference Fresco tests in a temporary copy | 57 passed |
| Reference modal/data-type tests in a temporary copy | 25 passed |

Reference probes confirmed the repeated-row consistency failure and
incomplete-handler runtime failure recorded in the design document.
Design commit: `396fd639`. `git diff --check` passed.
`make rule-check` passed; its tab check was skipped because GNU find
is unavailable, and its formatter check is disabled by repository
configuration.

## D1 verification

6 November 2026, D1, commit `af7ff947`: Added `core/effectRow.ml/.mli` and
`core/modality.ml/.mli`, with 28 unit tests registered in the no-database
unit suite. The main agent reviewed and integrated the implementation
from `.worktrees/modal-rows`. Independent review in a separate worktree
reported no findings and passed all 28 focused tests.

The tests exposed two further reference residual defects: selecting
the wrong repeated occurrence and changing higher-order row order.
A separate source investigation established the prefix construction
recorded in the design document. The initial unit run had one failing
residual law; the corrected implementation passes it. The API states
its sufficient-crossing contract and does not promise principality.

| Integrated check | Result |
|---|---|
| `make no-db` | Passed |
| `tests/handlers.tests` | 95 passed |
| `tests/effect_sugar.tests` | 44 passed |
| `opam exec -- ./run-tests nodb-unit-tests` | 72 passed, including 28 new tests |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual changed-file tab/trailing-whitespace check | Passed |
| `git diff --check` | Passed |

Finite tests cover 7,225 row pairs, 416,500 composition inputs, and
359,125 relative residual inputs. Source syntax and inference still
use the old representation; D1 provides the operations for D2--D6.
No milestone beyond the design comparison is complete yet.

## D2a verification

6 November 2026, D2a, commit `33d32716`: added `Abs`/`Any` quantifier
metadata, preserving it through structural substitution, freshening,
renaming, closure conversion, binder comparisons, and printing.
Existing callers default to `Any`. Legacy inference rejects unsupported `Abs` binders before
mutation. Added 32 unit tests and a recursive-alias acceptance test.
The main agent reviewed and integrated the changes from
`.worktrees/modal-types`.

Independent review found premature recursive alias unfolding in the
first guard implementation. The first integrated typecheck-example
run had seven missing-map errors; the implementation worktree also
had nine timeouts. The corrected guard reads raw declaration bodies
once per check. Only alias construction during desugaring permits
incomplete bodies. Independent review confirmed the correction and
reported no further findings.

| Integrated check | Result |
|---|---|
| `make no-db` | Passed |
| `tests/handlers.tests` | 95 passed |
| `tests/effect_sugar.tests` | 44 passed |
| `tests/polymorphism.tests` | 55 passed, including the new regression |
| `tests/typecheck_examples.tests` | 167 passed, 15 ignored by existing settings |
| `opam exec -- ./run-tests nodb-unit-tests` | 104 passed, including 32 new tests |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual changed-file tab/trailing-whitespace check | Passed |
| `git diff --check` | Passed |

Main, implementation, and review source snapshots match. A separate
reference test investigation checked all 43 Fresco acceptance files,
14 rejection files, and the combined modal/Fresco example. The design
document records representative pairs and additional Links coverage.
Read-only investigations also recorded the D3 parser transition and
the D4 context/assignment design.

## D2b verification

6 November 2026, D2b, commit `6255518a`: added contextual
`Arrow`/`LinearArrow` and `Modal`
types, scoped effect row aliases, structural traversals, substitution,
free-variable collection, kind utilities, and printers. Modal effect
arguments retain their identities, flags, duplicates, and order.
Ordinary linearity follows the modal payload. IR equality checks
scoped rows and relative mask multiplicities; legacy inference rejects
the new types before mutation. Added 30 unit tests.

Main review corrected unrestrictedness traversal through modal payloads.
Unit tests exposed premature recursive unfolding in IR equality; the
guard now checks raw bodies before comparison. Final audit added
session continuation comparison within modal/contextual equality.
Recursive modal IR equality remains explicitly unsupported until D8.
Independent review reported no further findings and passed all 30
focused tests. Main, implementation, and review snapshots match.

| Integrated check | Result |
|---|---|
| `make no-db` | Passed |
| `tests/handlers.tests` | 95 passed |
| `tests/effect_sugar.tests` | 44 passed |
| `tests/polymorphism.tests` | 55 passed |
| `tests/typecheck_examples.tests` | 167 passed, 15 ignored by existing settings |
| `opam exec -- ./run-tests nodb-unit-tests` | 134 passed, including 30 new tests |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual changed-file tab/trailing-whitespace check | Passed |
| `git diff --check` | Passed |

A source review also confirmed that the reference's ghost consistency
cases omit a required bound-variable check. The design records the
thesis rule and direct/source-level probes for D4.

## D3a verification

6 November 2026, D3a, commit `86863c58`: added `TypeParameter` descriptors carrying
ordinary and modal kinds. Abstract type arities, aliases, and recursive
applications retain these descriptors through structural operations.
Legacy consumers reject `Abs`, including unused parameters. Added
18 unit tests.

Independent review found that datatype desugaring could mutate an
earlier recursive type argument before rejecting a later `Abs`
parameter. Both argument-matching helpers now check the entire
parameter list before desugaring arguments. Two regression tests
failed before the fix and pass afterwards; they cover ordinary and
row applications of abstract, alias, and recursive declarations.
Independent review confirmed the fix and reported no further findings.
Main, implementation, and review source snapshots match.

| Integrated check | Result |
|---|---|
| `make no-db` | Passed |
| `tests/handlers.tests` | 95 passed |
| `tests/effect_sugar.tests` | 44 passed |
| `tests/polymorphism.tests` | 55 passed |
| `tests/typecheck_examples.tests` | 167 passed, 15 ignored by existing settings |
| `tests/type_print.tests` | 10 passed |
| `tests/desugar_datatypes.tests` | 25 passed |
| `opam exec -- ./run-tests nodb-unit-tests` | 152 passed, including 18 new tests |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual changed-file tab/trailing-whitespace check | Passed |
| `git diff --check` | Passed |

## D3b verification

6 November 2026, D3b, commit `4b8900dd`: added modal type syntax, positioned named effect
applications and masks, implicit arrow nodes, and modal binder kinds.
Sugar traversals and type-variable resolution preserve the new
structure and metadata. Legacy normalisation runs after import loading
and before module resolution, and in the built-in type-string reader.
Added 22 unit tests and five datatype regression tests.

Main review identified modal delimiter handling for variant/session
arguments and normalisation of imported signatures. Both were corrected
before integration. The final audit also added traversal of value-binding
quantifier lists. Independent review reported no remaining findings and
passed all 174 unit tests and 30 datatype tests. Main, implementation,
and review snapshots match.

The first unit run exposed an invalid legacy implicit-effect fixture.
The first datatype regression run had a new fixture calling a closed-row
function in the top-level `wild` context; the corrected fixture declares
that effect. The integrated handler suite timed out on its examples test
during parallel verification, then passed when rerun on its own.

| Integrated check | Result |
|---|---|
| `make no-db` | Passed |
| `tests/handlers.tests` | 95 passed on rerun |
| `tests/effect_sugar.tests` | 44 passed |
| `tests/polymorphism.tests` | 55 passed |
| `tests/typecheck_examples.tests` | 167 passed, 15 ignored by existing settings |
| `tests/type_print.tests` | 10 passed |
| `tests/desugar_datatypes.tests` | 30 passed, including five new tests |
| `tests/modules.tests` | 41 passed |
| `opam exec -- ./run-tests nodb-unit-tests` | 174 passed, including 22 new tests |
| Menhir conflicts | Zero in both baseline and changed grammar |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual changed-file tab/trailing-whitespace check | Passed |
| `git diff --check` | Passed |

The declaration investigation recorded effect-qualified operation names,
confirmed by the user, and migration of repeated operation-pattern clauses.
Reference probes also confirmed incorrect modal-kind classification of
nested and recursive datatype applications. The design records D4's
required correction and tests.

## D3c verification

6 November 2026, D3c, commit `55d7a760`: added named effect declarations with positioned
operation signatures, effect-qualified operations and patterns, handler
annotations, and `freeze(e)`. Generic traversals and free-variable
collection handle their children. Legacy entry points reject the new
constructs before processing the program; standalone type-variable
resolution preserves declarations for the later declaration resolver.
Added 21 unit test groups and seven datatype regression tests.

Tests and independent review found a qualified pattern position that
included its opening `<`, and a direct typed-transformation path that
reported an internal error for a qualified invocation. Both are fixed
and covered by tests. A missing legacy pattern-match case was also
completed. Imported-expression test fixtures were changed to value
bindings because the module loader imports declarations. Independent
review passed the final build, all 195 unit tests, and 37 datatype
tests, with no remaining findings. All three source snapshots match.

| Integrated check | Result |
|---|---|
| `make no-db` | Passed |
| `tests/handlers.tests` | 95 passed |
| `tests/effect_sugar.tests` | 44 passed |
| `tests/polymorphism.tests` | 55 passed |
| `tests/typecheck_examples.tests` | 167 passed, 15 ignored by existing settings |
| `tests/type_print.tests` | 10 passed |
| `tests/desugar_datatypes.tests` | 37 passed, including seven new tests |
| `tests/modules.tests` | 41 passed |
| `opam exec -- ./run-tests nodb-unit-tests` | 195 passed, including 21 new groups |
| Menhir conflicts | Zero in both baseline and changed grammar |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual changed-file tab/trailing-whitespace check | Passed |
| `git diff --check` | Passed |

Read-only D4 investigations specified separate kind classification and
well-formedness, a non-compressing variable-point reader, and monotype
requirements propagated through flexible row/presence dependencies.
Rigid row/presence variables remain monotype atoms subject to scope checks.
The design also records the selected quantified-type kind rule.

A further D4 investigation set the implementation order: non-mutating
point reads and modal kind classification, well-formedness, ordered
contexts and assignment, then scope exit and export. Raw recursive
declarations must retain their formal binders. Recursive declaration
identities also need a separator between their name and group number.

## D3d verification

6 November 2026, D3d, commit `59e61a6a`: added effect headers and contextual resolution state,
lexical effect/operation scopes, stable identities, repeated import reuse,
and declaration/handler structural checks. Annotated handlers resolve
unqualified clauses against their selected effect. Declaration parameters
have fresh rigid identities, retain modal kinds and inferred ordinary
subkinds, and cannot capture outer type variables. Free named variables,
including flexible variables, are rejected in operation signatures.
Added 30 unit test groups.

Main review identified that the existing type-variable pass permits free
flexible variables. A declaration-local check now rejects them without
changing legacy alias behaviour. Initial unit failures were invalid test
syntax and a wrong expected source offset; corrected fixtures pass.
Independent review found no further issues and passed its build, all
225 unit tests, 41 module tests and 37 datatype tests. Main, implementation,
and review source snapshots match.

| Integrated check | Result |
|---|---|
| `make no-db` | Passed |
| `tests/handlers.tests` | 95 passed |
| `tests/effect_sugar.tests` | 44 passed |
| `tests/polymorphism.tests` | 55 passed |
| `tests/typecheck_examples.tests` | 167 passed, 15 ignored by existing settings |
| `tests/type_print.tests` | 10 passed |
| `tests/desugar_datatypes.tests` | 37 passed |
| `tests/modules.tests` | 41 passed |
| `opam exec -- ./run-tests nodb-unit-tests` | 225 passed, including 30 new groups |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual changed-file tab/trailing-whitespace check | Passed |
| `git diff --check` | Passed |

Anonymous row syntax remains for contextual elaboration to check.
Operation signature typing, modal-kind checks, and the Fresco frontend
remain incomplete.

## D4a verification

6 November 2026, D4a, commit `f97e8e2a`: added `Unionfind.peek`, raw recursive declaration
binders, unambiguous declaration identities, and the `FrescoKind`
classification API. Classification uses callbacks and a finite Boolean
fixed point, preserving input points and declared modal kinds. Added
34 unit tests for type constructors, variables and solutions, recursive
arguments, captured binders, raw metadata, and both recorded reference
classification defects.

Independent review checked recursion, changing argument summaries,
captured bindings, callback scope, and input immutability. It found no
issues and passed its build, 259 unit tests, 37 datatype tests and
10 type-print tests. A separate metadata audit confirmed that existing
recursive record copies retain the callback and identity consumers treat
the identifier as opaque. Main, implementation, and review snapshots match.

| Integrated check | Result |
|---|---|
| `make no-db` | Passed |
| `tests/handlers.tests` | 95 passed |
| `tests/effect_sugar.tests` | 44 passed |
| `tests/polymorphism.tests` | 55 passed |
| `tests/typecheck_examples.tests` | 167 passed, 15 ignored by existing settings |
| `tests/type_print.tests` | 10 passed |
| `tests/desugar_datatypes.tests` | 37 passed |
| `tests/modules.tests` | 41 passed |
| `opam exec -- ./run-tests nodb-unit-tests` | 259 passed, including 34 new tests |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual new/changed-line tab/trailing-whitespace check | Passed |
| `git diff --check` | Passed |

Classification assumes well-formed types. D4b will validate every child,
ordinary and modal parameter kinds, and operation signatures. Its design
now distinguishes explicit ordinary `Mono` requirements from D4c's
syntactic monotype obligations, and requires closed effect signatures.

## D4b verification

6 November 2026, D4b, commit `85291100`: added separate type, effect-row and closed operation
signature checks in `FrescoKind`. The checks validate all children,
primary-kind structure, ordinary subkinds, modal parameter requirements,
effect descriptors and signature scopes. Recursive checks use raw bodies
and non-mutating reads. Added 40 unit test groups.

Main review found that the legacy kind ordering treats `Session` as
implying `Mono`, although session payloads may be polymorphic or modal.
The new checker now uses explicit entailment. Independent review found
that the existing empty-quantifier exception for `Base` also needed to
apply to `Mono`; empty `ForAll` wrappers now inherit their body's monotype
property. Main review also required Type-only effect parameters at the
public checking entry points. All corrections have regression tests.
The initial build rejected an OCaml keyword as a record label; the
callback is now named `lookup_effect`.

Independent review found no remaining issues and passed its build,
299 unit tests, 37 datatype tests, 10 type-print tests and source checks.
Main, implementation, and review source snapshots match.

| Integrated check | Result |
|---|---|
| `make no-db` | Passed |
| `tests/handlers.tests` | 95 passed |
| `tests/effect_sugar.tests` | 44 passed |
| `tests/polymorphism.tests` | 55 passed |
| `tests/typecheck_examples.tests` | 167 passed, 15 ignored by existing settings |
| `tests/type_print.tests` | 10 passed |
| `tests/desugar_datatypes.tests` | 37 passed |
| `tests/modules.tests` | 41 passed |
| `opam exec -- ./run-tests nodb-unit-tests` | 299 passed, including 40 new groups |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual new/changed-line tab/trailing-whitespace check | Passed |
| `git diff --check` | Passed |

A read-only D4c investigation specified strict assignment, dependency
movement, monotype requirements, and later ordinary refinement through
fresh stronger-kind unknowns. The checker does not yet connect to source
elaboration or term inference.

## Latest task and verification

6 November 2026, D4c: added abstract persistent contexts and strict checked
assignment. Context entries preserve declaration order and fixed kinds.
Assignment checks scope, occurs, ordinary/modal requirements and monotype
structure, moves younger flexible dependencies before its target, and
propagates monotype requirements through rows and presences. Added 49 unit
test groups, including ordinary refinement through stronger-kind aliases.

Main review found that the first point-cycle check rejected valid explicit
recursive points. Independent review also found a valid shared point
through a named declaration, and checked recursive binder shadowing.
Separate recursive-binder tracking and declaration-local point paths fix
these cases. Acceptance and rejection tests cover all three. One new test
fixture supplied an Any variable to List's Unl parameter; it now uses an
abstract constructor with an Any parameter for that traversal test.

Independent review found no remaining issues and passed its build,
348 unit tests, 37 datatype tests, 10 type-print tests and source checks.
Main, implementation, and review source snapshots match.

| Integrated check | Result |
|---|---|
| `make no-db` | Passed |
| `tests/handlers.tests` | 95 passed |
| `tests/effect_sugar.tests` | 44 passed |
| `tests/polymorphism.tests` | 55 passed |
| `tests/typecheck_examples.tests` | 167 passed, 15 ignored by existing settings |
| `tests/type_print.tests` | 10 passed |
| `tests/desugar_datatypes.tests` | 37 passed |
| `tests/modules.tests` | 41 passed |
| `opam exec -- ./run-tests nodb-unit-tests` | 348 passed, including 49 new groups |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual new/changed-line tab/trailing-whitespace check | Passed |
| `git diff --check` | Passed |

A read-only D4d investigation identified required scope-root rewriting,
liveness, escape checks, and detached export with variable metadata.
Scope exit, export, skeletons, consistency and term inference remain
incomplete.

## Next action

Implement D4d scope exit and detached type export. Rewrite solved variables
in explicit roots before deciding which local unknowns remain live. Preserve
variable constraints and sharing in exported data, and reject rigid escapes.
Skeletons, consistency, and contextual datatype elaboration follow.
