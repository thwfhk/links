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

D5, D6 and the prioritised D7 work are complete, independently reviewed,
checked and committed in milestones. Work is paused before D8 as requested.

On 7 November 2026, the user deferred socket examples, XML/forms, and
FFI/function locations to [future work](#future-todos). Their implementation
and dependent library/example migrations are outside the current D7 scope.
Prioritise readiness for general-purpose functional programming: ordinary
functions, polymorphism, data structures, modules, effects, and batch/REPL use.

The user's later instruction to finish the most important work narrows the
remaining D7 work to the annotation-scope fix, the default frontend switch and
checks of ordinary functional/modal programs, REPL use and compilation.
Remaining example migrations and exhaustive conversion of legacy regression
suites are deferred. Explicit legacy runs remain compatibility checks and do
not count as contextual coverage.

- D1--D3d provide row/modality operations, shared modal types, surface syntax,
  and effect/operation resolution. D4a--D4f1 provide kind checks, persistent
  contexts, checked assignment, shared-type scope exit/export, skeleton
  conversion, root substitution and quantifier opening.
- The default Fresco frontend checks and executes pure and modal source
  programs through contextual inference and shared IR/backend passes. Batch,
  REPL and compilation use it. Handler execution uses the existing
  `enable_handlers` setting. Explicit `--set=fresco=false` retains legacy
  compatibility; type errors do not trigger fallback.
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
| D7b3 | Escape continuations and contextual capture checks | `f09237bd` |
| D7b4a0 | Callback statement skeletons and frozen module names | `8cfe88a3` |
| D7b4a | Signed collection prelude with contextual callbacks | `0b2c0d3f` |
| D7b4b | Function, tuple, list and string helpers; inferred linear-call requirement | `efc1bca2` |
| D7b4c | Maybe, numeric, association and string-check helpers | `4e009da6` |
| D7c1a | Contextual Process, core actor primitives and ordinary spawn/receive | `ef94a794` |
| D7c1b | Actor locations/variants, mailbox polling and spawnWait | `b6902b96` |
| D7c1b1 | Bound type variables and argument positions in modal subtyping | `1822df37` |
| D7c1c | Full message suite and actor cases in mixed suites | `75072fad` |
| D7c2a | Session primitives, absolute messages and generic dual consistency | `2fc7f620` |
| D7c2b | Selection/offer inference, execution and contextual IR checks | `ceac5dce` |
| D7c2c1 | Split-end aliases and synchronisation helpers | `45ffa14b` |
| D7c2c2 | Callback session helpers and nested protocol skeleton duality | `0c46c06b` |
| D7c2d | CP checking, composition, linking and focused example migration | `568b9db3` |
| D7c2e1 | Ordinary session suite and module/polymorphic session cases | `79c2d173` |
| D7c2e2 | Curried modal/quantified results and ordinary session examples | `fe1586af` |
| D7c2e3a | Recursive/encoded protocols and staged linear-list modules | `f91695f5` |
| D7c2e3b | Generic protocol examples and raw recursive runtime bindings | `8b27a80b` |
| D7d3a | Remaining list, ASCII and date helpers | `27a0b58f` |
| D7d3b | Ordinary helper interfaces and linear variant aliases | `23c0b7ba` |
| D7d3c | Binary trees and parameter-dependent recursive value kinds | `48986cb7` |
| D7d3d0 | Empty switches with mode-directed results and existing partial-match behaviour | `160598c6` |
| D7d3d1 | Switch-function source migration and execution controls | `7468a1e4` |
| D7d3d2 | Church numerals and recursive bit-list examples | `d7ef09de` |
| D7d3d3a | Safe explicit width upcasts in source and contextual IR | `ed822373` |
| D7d3d3b | Extensible cases with checked row and callback contracts | `c3f1e695` |
| D7d3e1 | Buffered channels with checked message and helper contracts | `b37fb1ce` |
| D7e1 | Separate checked preparation and strict typed-lowering rechecks | `bec9d4f9` |
| D7e2a | Persistent fixities and file preprocessing | `1f535e58` |
| D7e2b | Canonical contextual prelude and custom batch bootstrap | `539bcd4d` |
| D7e3a | Contextual REPL definitions, environments, loading and recovery | `605f0454` |
| D7e3b | Contextual type search with isolated candidate checks | `b6fddccc` |
| D7e4 | Contextual JavaScript compilation without source evaluation | `32df0483` |
| D7e5a0 | Shared parameter annotation scopes and trusted rigid IR declarations | `debb83cc` |
| D7e5 | Default Fresco frontend and explicit legacy compatibility | This commit |

Each completed change was reviewed and checked. Earlier verification logs and
resolved review findings remain in Git history; retain the latest integrated
results here. The D3f list-parentheses correction is complete.

## Remaining work

D8 remains. Detailed language requirements are in the
specification; representations and algorithms are in the design. Each task
also requires the affected build/tests and review described in AGENTS.md.

| Task | Depends on | Completion check |
|---|---|---|
| D8: backends, documentation and final review | D7 | Interpreter/JS deep-handler checks, migration guide and selected suites pass; in-scope legacy effect inference is removed |

D4k supplies the type-annotation and effect-signature elaboration APIs needed
by D5 and D6.

D5 provides local signed recursion and the opt-in contextual source entry point.
D6 checks global signatures with absolute modalities and supplies the scoped
IR/backend support for its source tests. D7 makes Fresco the default frontend;
D8 performs the final backend audit.

### Coverage to retain across integration

- Use the design's reference Fresco pairs and `tests/freezeml.tests`. Check
  inferred type structure as well as successful execution.
- Cover higher-rank fields, zero/n-ary functions, explicit type operations,
  signed recursion and both successful and failed interactive definitions.
- Exercise deep/shallow handlers, handler parameters, qualified identities,
  repeated effects, omitted handler annotations/type arguments, explicit modal or
  polymorphic effect arguments, and `Any`-to-`Abs` refinement through lock access.
- Inventory records/variants, patterns, lists/tuples, modules, actors and
  existing sessions. Include `tests/messages.tests` for mailbox migration and
  preserve typed-IR/recheck settings. XML/forms, FFI/function locations and
  socket examples remain in the future-work inventory.
- Record general signatures needing independent effect variables and audit their
  concrete uses separately. The design lists the two-thunk test, `wait`, MVU and
  `curry`; do not claim a specialised migration preserves the original contract.
- D8 must resolve the existing interpreter close/link failure found in session
  integration: closing a sender before relay linking removes a buffer still
  read by link. Both frontends reproduce it. See the
  [session design](doc/modal-effects-design.md#d7-session-integration).
- Audit ghosts, exported variable requirements, recursive type consumers,
  lowering, optimisation and both backends. Keep excluded features outside scope.
  Retain the [deferred recursive-row inference gap and compatibility decisions](doc/modal-effects-design.md#consistency-guessing-and-monotype-unification).

### D7 and D8 milestones

Complete, independently review, test and commit each milestone before starting
implementation of the next. Continue through D7, then pause before D8 as the
user requested on 7 November 2026. The main agent owns integration and these records.

| Milestone | Completion checks |
|---|---|
| D7a: first-order primitives | Explicit contextual signatures cover pure/external primitives; source execution and modal rejection checks pass; remaining primitive categories are inventoried |
| D7b1: sections, patterns and updates | Projection/minus sections, negative patterns and record updates check and execute |
| D7b2a: regex syntax | Regex literals, splices and matching operations check and execute |
| D7b2b: ranges and comprehensions | List generators check and execute with existing evaluation order |
| D7b3: continuations | Escape typing, ordinary usage and execution match existing Links behaviour |
| D7b4a0: prelude prerequisites | Callback statement skeletons preserve effects; frozen module names resolve with scope |
| D7b4a: collection prelude | Signed collection helpers through `replicate` retain polymorphism, callback effects and ordinary usage |
| D7b4b: function, tuple and list helpers | Helpers through `unwords` migrate; specialised curry contract is recorded separately |
| D7b4c: remaining core helpers | Maybe, numeric, association and string checks migrate |
| D7c1a: core actors | `Process(a)`, Send/self/recv and ordinary spawn/receive check and execute with isolated mailboxes |
| D7c1b: actor variants | Locations, angel/client variants, haveMail and spawnWait check and execute on supported runtimes |
| D7c1b1: polymorphic export | Explicit modal-forall expressions passed to signed callers retain bound type variables through export |
| D7c1c: actor migration | Full messages suite and actor use sites migrate with existing feature settings |
| D7c2a: session primitives | Access points, send/receive/link/close execute; payload kinds, duality and ordinary usage checks pass |
| D7c2b: selection and offer | Continuation-changing selection and offer execute with typed IR; branch/session/result checks pass |
| D7c2c1: split-end helpers | EndBang/EndQuery, wait/closeBang/makeEndBang/linkSync have contextual signatures and execute |
| D7c2c2: callback session helpers | Fork/connection helpers execute with explicit spawned-callback contracts and no session-failure support |
| D7c2d: CP | All CP forms check/lower; composition, capture and linking examples execute |
| D7c2e1: session regression migration | Ordinary session suite and module/polymorphism cases retain their settings and intended checks |
| D7c2e2: ordinary session examples | Curried modal/polymorphic results check; finite calculator, split-end and channel examples migrate and execute |
| D7c2e3a: recursive and encoded protocols | Calculators, ATM, encoded choice and linear-list helpers typecheck; local executions and generic controls pass |
| D7c2e3b: remaining generic protocols | State, process encoding, authentication and recursive duality examples typecheck; terminating cases execute |
| D7d3a: remaining list, character and date helpers | Existing ordering, callback effects and pure/Wild contracts pass source execution checks |
| D7d3b: ordinary helper interfaces | Remaining list/Maybe helpers, aliases and composition interfaces have explicit contracts and source checks |
| D7d3c: binary trees | Comparator and binary-tree modules migrate; existing operations and contextual callbacks execute |
| D7d3d0: empty switches | Empty-variant uses and legacy partial-match behaviour check/lower with preserved result and usage rules |
| D7d3d1: switch functions | Named, anonymous and nested switch functions execute; recursion, partial matches and syntax errors retain their checks |
| D7d3d2: Church numerals and bit lists | First-class polymorphism and recursive callback examples check and execute bounded results |
| D7d3d3a: explicit upcasts | Explicit variant widening and record narrowing retain source checks, payload types, row requirements and typed-IR validation |
| D7d3d3b: extensible cases | Open-variant rows, negative patterns and upcasts check and execute |
| D7d3e1: buffered channels | Generic queues retain FIFO order, waiting readers and payload requirements through actual execution |
| D7e1: checked preparation | Separate checking/lowering from evaluation; contextual lowering rechecks validate annotations and result types |
| D7e2a: persistent parsing state | Operator fixities survive successful inputs and file preprocessing matches string input |
| D7e2b: prelude and batch | Canonical prelude loading and custom/empty preludes work through Fresco |
| D7e3a: REPL and ordinary directives | Definitions, loading and environments use persistent contextual state with failure recovery |
| D7e3b: contextual type search | Type queries elaborate and match through isolated contextual inference without changing live state |
| D7e4: JavaScript compilation | Existing compile options consume contextual IR without evaluating the source program |
| D7e5a0: parameter annotation scopes | Named type, row and presence variables share the intended parameter/body scope; annotations elaborate once and preserve scope-exit checks |
| D7e5: default frontend | Fresco is the default; functional/modal source checks and no-selector batch/REPL/compile checks pass; old effect syntax rejects; compatibility routes are explicit |
| D8a: backend execution | Actual interpreter and JavaScript deep-handler execution covers nesting, repeated identities, parameters and closures; interpreter shallow execution and JavaScript rejection remain checked |
| D8b: removal and final review | In-scope legacy inference routes are removed; recursive consumers and exports are reviewed; migration guide and final selected suites pass |

D7a (`1f7ff34e`), D7b1 (`4fad3532`) and D7b2a (`db0d3a75`) are complete.
D7b2b (`72e47dbc`) and D7b3 (`f09237bd`) are complete. D7b4a0 (`8cfe88a3`) is complete. D7b4a collection migration (`0b2c0d3f`) is complete. D7b4b (`efc1bca2`) is complete. D7b4c (`4e009da6`) is complete. D7c1a core actors (`ef94a794`) and D7c1b actor variants are complete.
D7c1b1 polymorphic export is complete. D7c1c actor migration is complete. D7c2a session primitives are complete. D7c2b selection/offer is complete. D7c2c1 split-end helpers are complete. D7c2c2 callback helpers are complete. D7c2d CP is complete. D7c2e1 ordinary session regression migration is complete. D7c2e2 ordinary examples are complete. D7c2e3a recursive/encoded protocol examples are complete. D7c2e3b remaining generic protocols are complete. D7d3a ordinary list, character and date helpers are complete. D7d3b ordinary helper interfaces are complete. D7d3c binary trees are complete. D7d3d0 empty switches is complete. D7d3d1 switch functions is complete. D7d3d2 Church numerals and bit lists is complete. D7d3d3a explicit upcasts is complete; D7d3d3b extensible cases is complete. D7d3e1 buffered channels is complete. D7e1 checked preparation is complete. D7e2a persistent parsing state is complete. D7e2b contextual prelude loading is complete. D7e3a contextual REPL is complete. D7e3b contextual type search is complete. D7e4 contextual JavaScript compilation is complete. D7e5a0 parameter annotation scopes are complete. The prioritised D7e5 default switch is complete. Work is paused before D8. Later boundaries may be split further when a dependency needs
its own review and checks.

### Future TODOs

Deferred by the user on 7 November 2026. These items retain their identifiers
for reference and require separate scheduling. They are outside the current
D7 completion checks and are not added to D8. Library and example migrations
that require these features are deferred with them; this updates the earlier
assignments in the design's migration inventory.

| Item | Completion checks when resumed |
|---|---|
| D7c2e3c: socket examples | SMTP/IRC models typecheck; local dummy execution passes |
| D7d1: XML and forms | XML, form/page constructs and their prelude dependencies check and execute |
| D7d2: FFI and function locations | Foreign declarations, locations and FFI dependencies survive checking and lowering |
| D7d3e2: console example | Console helpers and finite actor games retain their callback contracts and results |
| D7e5 migration remainder | Convert remaining legacy regression assertions and standalone examples using the recorded inventory; preserve intended rejection causes and complete type expectations |

The console example is deferred following the user's concern about time spent
on work peripheral to modal effects. Prioritise D7 frontend integration; this
scope choice is recorded for review in the design.

The remaining legacy-suite and example conversion was deferred after the user
asked to focus on finishing the most important work. Its inventory is
`/tmp/links-d7e5-inventory.md`, independently reviewed in
`/tmp/links-d7e5-inventory-review-summary.log`. Keep existing migrated cases on
Fresco and label the remaining suites as legacy compatibility. D8's legacy
inference removal must resolve this compatibility dependency before deleting
the retained route.

The formlet State helpers retain their existing capture contract and are deferred
with D7d1. This implementation choice is [recorded for review](doc/modal-effects-design.md#d7-ordinary-library-inventory).

## Recorded decisions

The user decisions of 6--7 November 2026 are recorded in the specification
and design:

- [Language rules and reference choices](doc/modal-effects-design.md#language-decisions-and-their-reasons).
- [Effect matching order](doc/modal-effects-design.md#parameterised-effect-matching-order).
- [Linearity, global signatures and initial effects](doc/modal-effects-design.md#value-linearity-and-legacy-effect-sugar).
- [D4 ghost kinds and instantiation checks](doc/modal-effects-design.md#subtyping-and-instantiation-information).
- [D4k signature binders and ordinary row arguments](doc/modal-effects-design.md#contextual-annotation-and-declaration-elaboration).

### D7 choices awaiting review

The marked choices remain implementation decisions for review; they do not
block the prioritised D7 completion checks.

1. Actor and session contracts: `spawnWait` body/result kinds, absolute message
   payloads, spawned callback modalities and `Wild` for selection/offer.
   See [actors](doc/modal-effects-design.md#d7-actor-integration) and
   [sessions](doc/modal-effects-design.md#d7-session-integration).
2. Encoded-choice message modalities and staged linear-list modules.
   See [session migration](doc/modal-effects-design.md#d7-session-migration-inventory).
3. Shared ambient contexts in helper interfaces, the tree comparator, Church
   numerals and extensible cases; deferred State and console examples.
   See [prelude migration](doc/modal-effects-design.md#d7-prelude-migration) and
   [ordinary libraries](doc/modal-effects-design.md#d7-ordinary-library-inventory).
4. Ordinary-arrow guessing for unresolved callable types and continuation access.
   See [linear results](doc/modal-effects-design.md#d7-inferred-linear-results) and
   [continuations](doc/modal-effects-design.md#d7-continuations).
5. Typed-lowering rechecks, default/custom prelude preparation, contextual type
   search, compile input/output ordering and deferred full migration.
   See [frontend integration](doc/modal-effects-design.md#d7-frontend-integration-plan).
6. Shared parameter annotation names and deferred names for later-result forall
   binders. See [annotation scopes](doc/modal-effects-design.md#contextual-annotation-and-declaration-elaboration).

## Latest task and verification

7 November 2026, D7e5, base `debb83cc`: Fresco is the default for batch,
REPL/type search and compilation. Bare `--fresco` remains affirmative; explicit
legacy selection and existing `--set` precedence remain available. Deferred
legacy assertions use labelled compatibility configurations; existing migrated
cases retain their explicit Fresco selector. The [design](doc/modal-effects-design.md#d7-frontend-integration-plan)
records the priority/scope and selector decisions.

Independent review passed default/selector cases, real REPL and compile paths,
and mixed-suite overrides: `/tmp/links-d7e5-review-summary.log`.
Review initially found that bare `--fresco` disabled the new true default,
producing `Abs binders require contextual type checker` in migrated cases.
Optional affirmative CLI metadata fixes that setting while preserving other
flags' behaviour. The original review log is
`/tmp/links-d7e5-review-compatibility.log`. Selector tests also establish the
existing precedence of `--set` writes; global timestamp handling is unchanged.
All eight writer hashes matched. Writers finished and the combined diff was
reviewed before integration.

The final build and all checks passed: 1,529 unit tests, 517 contextual regression
cases, 575 legacy compatibility cases, eleven no-selector REPL scenarios and
ten compile scenarios. Sixteen existing regression cases remain ignored.
Compatibility assertions are not evidence of contextual support. Logs are in
`/tmp/links-d7e5-verification`; `revision.txt` and `source.sha256` identify the
tested source. `frontend-counts.json` records per-suite routing. Frozen hashes
and added/new-line whitespace passed.

| Command | Result | Log |
|---|---|---|
| `make no-db` | Passed | `build.log` |
| `opam exec -- ./run-tests nodb-unit-tests` | 1,529 passed | `unit.log` |
| `python3 tests/fresco_repl.py` | 11 passed | `repl.log` |
| `python3 tests/fresco_compile.py` | 10 groups passed, including legacy selector controls | `compile.log` |
| `./test-harness tests/fresco_default.tests` | 13 contextual, 4 legacy compatibility passed | `fresco_default.log` |
| `./test-harness tests/fresco_batch.tests` | 10 contextual, 1 legacy compatibility passed | `fresco_batch.log` |
| `./test-harness tests/fresco_examples.tests` | 36 contextual passed | `fresco_examples.log` |
| `./test-harness tests/switch_functions.tests` | 14 contextual passed | `switch_functions.log` |
| `./test-harness tests/records.tests` | 30 legacy compatibility passed | `records.log` |
| `./test-harness tests/patterns.tests` | 34 legacy compatibility passed, 2 ignored | `patterns.log` |
| `./test-harness tests/binaryTrees.tests` | 28 contextual passed | `binaryTrees.log` |
| `./test-harness tests/handlers.tests` | 95 legacy compatibility passed | `handlers.log` |
| `./test-harness tests/effect_sugar.tests` | 44 legacy compatibility passed | `effect_sugar.log` |
| `./test-harness tests/fresco.tests` | 114 contextual passed | `fresco.log` |
| `./test-harness tests/fresco_typecheck.tests` | 9 contextual passed | `fresco_typecheck.log` |
| `./test-harness tests/fresco_modal.tests` | 20 contextual passed | `fresco_modal.log` |
| `./test-harness tests/fresco_prelude.tests` | 86 contextual passed | `fresco_prelude.log` |
| `./test-harness tests/fresco_actors.tests` | 49 contextual passed | `fresco_actors.log` |
| `./test-harness tests/fresco_sessions.tests` | 35 contextual passed | `fresco_sessions.log` |
| `./test-harness tests/fresco_cp.tests` | 22 contextual passed | `fresco_cp.log` |
| `./test-harness tests/fresco_session_examples.tests` | 24 contextual passed | `fresco_session_examples.log` |
| `./test-harness tests/messages.tests` | 11 contextual passed | `messages.log` |
| `./test-harness tests/sessions.tests` | 13 contextual passed | `sessions.log` |
| `./test-harness tests/typed_ir.tests` | 1 contextual, 25 legacy compatibility passed | `typed_ir.log` |
| `./test-harness tests/functions.tests` | 1 contextual, 32 legacy compatibility passed | `functions.log` |
| `./test-harness tests/polymorphism.tests` | 1 contextual, 54 legacy compatibility passed | `polymorphism.log` |
| `./test-harness tests/typecheck_examples.tests` | 25 contextual, 145 legacy compatibility passed, 14 ignored | `typecheck_examples.log` |
| `./test-harness tests/continuations.tests` | 1 contextual, 14 legacy compatibility passed | `continuations.log` |
| `./test-harness tests/modules.tests` | 1 contextual, 40 legacy compatibility passed | `modules.log` |
| `./test-harness tests/freezeml.tests` | 3 contextual, 57 legacy compatibility passed | `freezeml.log` |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter disabled | `rule-check.log` |
| Frozen source hashes and `git diff --check` | Passed | `source-check.log`, `diff-check.log` |

## Confirmed D6 decisions

7 November 2026: the user confirmed both D6 choices. The
[design](doc/modal-effects-design.md#d6-scoped-effects-in-ir) records handler
result inference from return clauses and source-only modal checks.
Documentation-only update: text and whitespace checked.

## Next action

Paused after the prioritised D7 completion, before D8, as requested.
Await the user's instruction before backend execution/audit or further migration.
D8 must test the existing backends through actual execution and address the
recorded interpreter close/link failure. Legacy inference removal depends on
resolving the deferred compatibility migration.

Remaining legacy-suite/example conversion is in [future work](#future-todos).
The inventory and its independent review remain in
`/tmp/links-d7e5-inventory.md` and
`/tmp/links-d7e5-inventory-review-summary.log`. Later-result forall annotation
names and inferred free-variable kind displays remain follow-ups; the source
checker still enforces stored ordinary-kind requirements. Marked design choices
are collected [above](#d7-choices-awaiting-review).
