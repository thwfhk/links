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
integrated, tested, and independently reviewed. Shared type integration,
syntax, Fresco inference, and migration remain incomplete.

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
- [ ] Implement and test modal syntax and scoped effect rows.
- [ ] Refactor type inference to follow Fresco.
- [ ] Implement modal inference and run the first working example.
- [ ] Complete Links integration and migrate affected programs.
- [ ] Complete integration tests, documentation, and review.

## Working procedure

- Start each implementation task by reading `AGENTS.md`, this plan,
  the design document, and the relevant source files. The main agent
  owns design, integration, verification, progress records, and commits.
- Use fresh Astra High subagents for bounded investigations, changes,
  and reviews; use extra-high effort for difficult tasks. Give each
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

## Latest task and verification

6 November 2026, D1: Added `core/effectRow.ml/.mli` and
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

## Next action

Implement D2: integrate scoped rows and modal types into the shared
type representation, including all type traversals, substitution,
free-variable collection, and printers. Keep the compiler building
and preserve record/variant row behaviour. Then proceed to D3 and D4
using the dependencies in the design document.
