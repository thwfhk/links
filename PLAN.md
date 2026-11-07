# Modal effects in Links

## Goal and document roles

Implement modal effect types with scoped rows of named effects and replace
Links' inference engine with Fresco on `modal-effects`.

This file owns high-level progress, dependencies, completion checks,
verification results and the next action. [The specification](doc/modal-effects-spec.md)
owns language behaviour. [The design](doc/modal-effects-design.md) owns concrete
implementation decisions, reasons, internal invariants and source comparisons.
[AGENTS.md](AGENTS.md) owns working procedures and build/test commands.

## Current status

D5 and D6 are complete, independently reviewed and checked in separate
commits. D7 integration is in progress.

- D1--D3d provide row/modality operations, shared modal types, surface syntax,
  and effect/operation resolution. D4a--D4f1 provide kind checks, persistent
  contexts, checked assignment, shared-type scope exit/export, skeleton
  conversion, root substitution and quantifier opening.
- The opt-in `--fresco` batch and REPL frontend checks and executes pure and
  modal source programs through contextual inference and shared IR/backend
  passes. Handler execution uses the existing `enable_handlers` setting. The
  default frontend retains `TypeSugar.Check` until D7.
- D4f2--D4i add skeleton expansion/scope exit preserving ghosts, flexible
  requirement refinement, contextual recursive operations, consistency,
  guessing and monotype unification.
- D4j adds subtyping, constraint collection/solving and `look`, with explicit
  scoped polymorphic/modal instantiations and ordinary session comparison.
- D4k elaborates source annotations, written function signatures, type
  arguments, aliases and closed effect declarations through contextual kind
  checking, with positioned errors. D5 adds pure source term inference, runtime
  integration and persistent interactive state. D6 adds modal operations,
  handlers, scoped IR evidence and source execution. Migration remains.
- D3e removes higher-order effect flags, syntax and row rules. Ordinary
  operation arguments and results must be absolute.
- D3f implements `List A`, combined kind annotations and angle-bracket
  handled-effect annotations, for example `handle <Reader> (...)`.
- D4a2 implements the thesis' quantified-type classification while retaining
  declared binder requirements. D4g adds flexible requirement refinement.

Nested list element types require parentheses. The parser and both type
printers follow this rule.
The most recent compiler verification is recorded below. Passing legacy suites
checks compatibility during construction; it does not complete Fresco inference.

## Completed work

| Task | Result | Commit |
|---|---|---|
| Design comparison | Thesis/reference comparison and initial review | `396fd639` |
| D1 | Scoped effect rows and modalities | `af7ff947` |
| D2a | Modal quantifier metadata | `33d32716` |
| D2b | Contextual arrows, modal types and traversals | `6255518a` |
| D3a | Modal kinds on declaration parameters | `86863c58` |
| D3b | Modal type/binder syntax and implicit arrows | `4b8900dd` |
| D3c | Effect declarations, qualification, handlers and freezing syntax | `55d7a760` |
| D3d | Effect/operation resolution and structural declaration checks | `59e61a6a` |
| D4a | Non-mutating inspection and recursive modal-kind classification | `f97e8e2a` |
| D4b | Type/effect well-formedness and closed signature checks | `85291100` |
| D4c | Persistent contexts and checked assignment | `39107efb` |
| D4d1 | Shared-type scope exit with rewritten roots | `81c883b9` |
| D4d2 | Detached export with variable metadata | `c143fb84` |
| D4e | Recursive skeletons and checked shared-type conversion | `bb94d506` |
| D4f1 | Skeleton free variables, root substitution and quantifier opening | `7af62207` |
| D3e | Remove higher-order effect declarations and row rules | `29a9ba43` |
| D3f | Prefix list types, combined kinds and handler delimiters | `aa9358e4` |
| D4a2 | Thesis quantified-type classification | `41b96256` |
| D3f correction | Require parentheses around nested list element types | `02f79356` |
| D4f2 | Skeleton solution expansion and scope exit preserving ghosts | `609c02fe` |
| D4g | Ordinary/modal requirement refinement and detached restoration | `dac6f8fc` |
| D4h | Contextual application, unfolding, session duality and recursive comparison | `d12f864a` |
| D4i | Persistent monotype unification, consistency and guessing | `e425984c` |
| D4j | Subtyping, constraint collection/solving, `look` and session compatibility checks | `7b4f78be` |
| D4j follow-up | Direct skeleton kind checking with ordinary ghosts at `Abs` | `81cfc187` |
| D4k | Contextual source annotation and declaration elaboration | `8a5b5743` |
| D5 | Pure source inference, opt-in frontend, shared IR/backend execution and persistent state | `4f12cd67` |
| D6 | Modal source inference, complete handlers, inferred effect arguments and scoped IR/backend support | `92d48828` |
| D7a | Contextual first-order primitives and recursive primitive aliases | `1f7ff34e` |
| D7b1 | Sections, negative patterns and record updates | `4fad3532` |
| D7b2a | Regex syntax, splices, matching and replacement | `db0d3a75` |
| D7b2b | Ranges, list comprehensions, filters and ordering | `72e47dbc` |
| D7b3 | Escape continuations and contextual capture checks | This commit |

Each completed change was reviewed and checked. Earlier verification logs and
resolved review findings remain in Git history; retain the latest integrated
results here. The D3f list-parentheses correction is complete.

## Remaining work

All tasks below are incomplete. Detailed language requirements are in the
specification; representations and algorithms are in the design. Each task
also requires the affected build/tests and review described in AGENTS.md.

| Task | Depends on | Completion check |
|---|---|---|
| D7: Links integration and migration | D5--D6 | Syntax/primitive inventory is covered; batch, REPL and typed rechecks use Fresco; programs migrate and old effect syntax rejects |
| D8: backends, documentation and final review | D7 | Interpreter/JS deep-handler checks, migration guide and selected suites pass; in-scope legacy effect inference is removed |

D4k supplies the type-annotation and effect-signature elaboration APIs needed
by D5 and D6.

D5 provides local signed recursion and the opt-in contextual source entry point.
D6 checks global signatures with absolute modalities and supplies the scoped
IR/backend support for its source tests. Switch the default frontend in D7;
D8 performs the final backend audit.

### Coverage to retain across integration

- Use the design's reference Fresco pairs and `tests/freezeml.tests`. Check
  inferred type structure as well as successful execution.
- Cover higher-rank fields, zero/n-ary functions, explicit type operations,
  signed recursion and both successful and failed interactive definitions.
- Exercise deep/shallow handlers, handler parameters, qualified identities,
  repeated effects, omitted handler annotations/type arguments, explicit modal or
  polymorphic effect arguments, and `Any`-to-`Abs` refinement through lock access.
- Inventory records/variants, patterns, lists/tuples, modules, actors, XML/web
  forms, FFI and existing sessions. Include `tests/messages.tests` for mailbox
  migration and preserve typed-IR/recheck settings.
- Record general signatures needing independent effect variables and audit their
  concrete uses separately. The design lists the two-thunk test, `wait`, MVU and
  `curry`; do not claim a specialised migration preserves the original contract.
- Audit ghosts, exported variable requirements, recursive type consumers,
  lowering, optimisation and both backends. Keep excluded features outside scope.
  Retain the [deferred recursive-row inference gap and compatibility decisions](doc/modal-effects-design.md#consistency-guessing-and-monotype-unification).

### D7 and D8 milestones

Complete, independently review, test and commit each milestone before starting
implementation of the next. The main agent owns integration and these records.

| Milestone | Completion checks |
|---|---|
| D7a: first-order primitives | Explicit contextual signatures cover pure/external primitives; source execution and modal rejection checks pass; remaining primitive categories are inventoried |
| D7b1: sections, patterns and updates | Projection/minus sections, negative patterns and record updates check and execute |
| D7b2a: regex syntax | Regex literals, splices and matching operations check and execute |
| D7b2b: ranges and comprehensions | List generators check and execute with existing evaluation order |
| D7b3: continuations | Escape typing, ordinary usage and execution match existing Links behaviour |
| D7b4: prelude foundations | Signed collection helpers retain polymorphism and callback effects |
| D7c1: actors | `Process(a)`, absolute mailbox types and isolated spawned contexts check and execute; migrated `messages.tests` passes |
| D7c2: sessions | Existing session primitives, selection/offer and CP check and execute |
| D7d1: XML and forms | XML, form/page constructs and their prelude dependencies check and execute |
| D7d2: FFI and locations | Foreign declarations, locations and FFI dependencies survive checking and lowering |
| D7d3: libraries and examples | In-scope libraries and examples migrate; independent-effect contracts are recorded separately from specialised uses |
| D7e: frontend and source migration | Default batch, REPL, JavaScript compilation and typed rechecks use Fresco; selected suites and handler examples migrate; old effect syntax rejects |
| D8a: backend execution | Actual interpreter and JavaScript deep-handler execution covers nesting, repeated identities, parameters and closures; interpreter shallow execution and JavaScript rejection remain checked |
| D8b: removal and final review | In-scope legacy inference routes are removed; recursive consumers and exports are reviewed; migration guide and final selected suites pass |

D7a (`1f7ff34e`), D7b1 (`4fad3532`) and D7b2a (`db0d3a75`) are complete.
D7b2b (`72e47dbc`) and D7b3 are complete. D7b4 is next. Later boundaries may be split further when a dependency needs
its own review and checks.

## Recorded decisions

The user decisions of 6--7 November 2026 are recorded in the specification
and design:

- [Language rules and reference choices](doc/modal-effects-design.md#language-decisions-and-their-reasons).
- [Effect matching order](doc/modal-effects-design.md#parameterised-effect-matching-order).
- [Linearity, global signatures and initial effects](doc/modal-effects-design.md#value-linearity-and-legacy-effect-sugar).
- [D4 ghost kinds and instantiation checks](doc/modal-effects-design.md#subtyping-and-instantiation-information).
- [D4k signature binders and ordinary row arguments](doc/modal-effects-design.md#contextual-annotation-and-declaration-elaboration).

## Latest task and verification

7 November 2026, D7b3, base `72e47dbc`: escape continuations are complete,
including repeated invocation, supplied polymorphic/modal results, ordinary
usage and capture-context checks. [The design](doc/modal-effects-design.md#d7-continuations)
records the contextual continuation rule and its restrictions for user review.

Independent review found and resolved a handler-escape error in the proposed
absolute continuation type. The final contextual arrow retains the capture
context. No findings remain. All writers finished and the combined diff was
inspected before integrated checks. The six source/test hashes in
`/tmp/links-d7b3-verification/source.sha256` still match after testing. Logs below
are in that directory; documentation was updated afterwards.

| Command | Result | Log |
|---|---|---|
| `make no-db` | Passed | `build.log` |
| `opam exec -- ./run-tests nodb-unit-tests` | 1,274 passed | `unit.log` |
| `./test-harness tests/fresco.tests` | 54 passed | `fresco.log` |
| `./test-harness tests/fresco_typecheck.tests` | 2 passed | `fresco_typecheck.log` |
| `./test-harness tests/fresco_modal.tests` | 20 passed | `fresco_modal.log` |
| `./test-harness tests/handlers.tests` | 95 passed | `handlers.log` |
| `./test-harness tests/effect_sugar.tests` | 44 passed | `effect_sugar.log` |
| `./test-harness tests/typed_ir.tests` | 26 passed | `typed_ir.log` |
| `./test-harness tests/continuations.tests` | 15 passed | `continuations.log` |
| `./test-harness tests/polymorphism.tests` | 55 passed | `polymorphism.log` |
| `./test-harness tests/typecheck_examples.tests` | 167 passed; 15 ignored | `typecheck_examples.log` |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter disabled | `rule-check.log` |
| Source hashes, tabs and trailing whitespace; `git diff --check` | Passed | `source-check.log`, `diff-check.log` |

Focused source checking/execution passed 180 cases in
`/tmp/links-d7b3-agent-source.log`. Independent review passed 19 typed-IR
execution/rejection probes in `/tmp/links-d7b3-review-final-source.log`.
The original failure is in `/tmp/links-d7b3-review-unsound.log`.
Earlier milestone results remain in Git history and their
`/tmp/links-d7*-verification` directories.

## Confirmed D6 decisions

7 November 2026: the user confirmed both D6 choices. The
[design](doc/modal-effects-design.md#d6-scoped-effects-in-ir) records handler
result inference from return clauses and source-only modal checks.
Documentation-only update: text and whitespace checked.

## Next action

Implement D7b4 prelude foundations. Independently review, test and commit before
D7c1 actors. Continue through the remaining milestones
without a pause. Both D6 choices are confirmed.
