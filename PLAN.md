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
| D7c2e3a | Recursive/encoded protocols and staged linear-list modules | This commit |

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
| D7c2e3c: socket models | SMTP/IRC models typecheck; local dummy execution passes |
| D7d1: XML and forms | XML, form/page constructs and their prelude dependencies check and execute |
| D7d2: FFI and locations | Foreign declarations, locations and FFI dependencies survive checking and lowering |
| D7d3: libraries and examples | In-scope libraries and examples migrate; independent-effect contracts are recorded separately from specialised uses |
| D7e: frontend and source migration | Default batch, REPL, JavaScript compilation and typed rechecks use Fresco; selected suites and handler examples migrate; old effect syntax rejects |
| D8a: backend execution | Actual interpreter and JavaScript deep-handler execution covers nesting, repeated identities, parameters and closures; interpreter shallow execution and JavaScript rejection remain checked |
| D8b: removal and final review | In-scope legacy inference routes are removed; recursive consumers and exports are reviewed; migration guide and final selected suites pass |

D7a (`1f7ff34e`), D7b1 (`4fad3532`) and D7b2a (`db0d3a75`) are complete.
D7b2b (`72e47dbc`) and D7b3 (`f09237bd`) are complete. D7b4a0 (`8cfe88a3`) is complete. D7b4a collection migration (`0b2c0d3f`) is complete. D7b4b (`efc1bca2`) is complete. D7b4c (`4e009da6`) is complete. D7c1a core actors (`ef94a794`) and D7c1b actor variants are complete.
D7c1b1 polymorphic export is complete. D7c1c actor migration is complete. D7c2a session primitives are complete. D7c2b selection/offer is complete. D7c2c1 split-end helpers are complete. D7c2c2 callback helpers are complete. D7c2d CP is complete. D7c2e1 ordinary session regression migration is complete. D7c2e2 ordinary examples are complete. D7c2e3a recursive/encoded protocol examples are complete. D7c2e3b is next. Later boundaries may be split further when a dependency needs
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

7 November 2026, D7c2e3a, base `fe1586af`: ATM, recursive/simulated
calculators, encoded choice and two staged linear-list modules use Fresco.
The recursive calculator returns `84`; ATM returns `(16, 0, Just(128))`;
the simulated calculator returns `42`. Choice and linear-list callbacks retain
the caller's handled effects. The
[migration inventory](doc/modal-effects-design.md#d7-session-migration-inventory)
records the absolute variant wrapper and staging choices for review.

Recursive offer exposed separate checked copies of one declaration reaching
row consistency. Row joins now use the existing validation and sharing step
used by ordinary joins. Thirty-three focused session tests passed; five
selected review units preserve rejection of conflicting declaration bodies.
Actual executions and generic positive/negative controls passed. Review record:
`/tmp/links-d7c2e3a-review-summary.log`.

Initial integrated testing found two legacy session-failure servers importing
the migrated linear-list module. Restore the original modules and stage the
Fresco definitions separately; both affected suites passed after review and
rerun. The initial failure log and source hashes are retained with `-initial`
suffixes. Core/unit sources remained unchanged after that correction, so their
build and unit results remain applicable.

All writers finished and the combined diff was reviewed before each integrated
check. The build, 1,448 unit tests and 819 regression cases passed; 15 existing
example cases remain ignored. Source hashes still match. Logs below are in
`/tmp/links-d7c2e3a-verification`; `revision.txt`, `source.sha256` and the
initial hash record identify the tested sources. Documentation was updated
afterwards.

| Command | Result | Log |
|---|---|---|
| `make no-db` | Passed | `build.log` |
| `opam exec -- ./run-tests nodb-unit-tests` | 1,448 passed | `unit.log` |
| `./test-harness tests/fresco.tests` | 70 passed | `fresco.log` |
| `./test-harness tests/fresco_typecheck.tests` | 2 passed | `fresco_typecheck.log` |
| `./test-harness tests/fresco_modal.tests` | 20 passed | `fresco_modal.log` |
| `./test-harness tests/fresco_prelude.tests` | 45 passed | `fresco_prelude.log` |
| `./test-harness tests/fresco_actors.tests` | 49 passed | `fresco_actors.log` |
| `./test-harness tests/fresco_sessions.tests` | 35 passed | `fresco_sessions.log` |
| `./test-harness tests/fresco_cp.tests` | 22 passed | `fresco_cp.log` |
| `./test-harness tests/fresco_session_examples.tests` | 14 passed | `fresco_session_examples.log` |
| `./test-harness tests/messages.tests` | 11 passed | `messages.log` |
| `./test-harness tests/sessions.tests` | 13 passed | `sessions.log` |
| `./test-harness tests/handlers.tests` | 95 passed | `handlers.log` |
| `./test-harness tests/effect_sugar.tests` | 44 passed | `effect_sugar.log` |
| `./test-harness tests/typed_ir.tests` | 26 passed | `typed_ir.log` |
| `./test-harness tests/functions.tests` | 33 passed | `functions.log` |
| `./test-harness tests/polymorphism.tests` | 55 passed | `polymorphism.log` |
| `./test-harness tests/typecheck_examples.tests` | 169 passed, 15 ignored | `typecheck_examples.log` |
| `./test-harness tests/continuations.tests` | 15 passed | `continuations.log` |
| `./test-harness tests/modules.tests` | 41 passed | `modules.log` |
| `./test-harness tests/freezeml.tests` | 60 passed | `freezeml.log` |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter disabled | `rule-check.log` |
| Source hashes, added-line whitespace; `git diff --check` | Passed | `source-check.log`, `diff-check.log` |

## Confirmed D6 decisions

7 November 2026: the user confirmed both D6 choices. The
[design](doc/modal-effects-design.md#d6-scoped-effects-in-ir) records handler
result inference from return clauses and source-only modal checks.
Documentation-only update: text and whitespace checked.

## Next action

Implement D7c2e3b remaining generic protocols, then D7c2e3c socket models.
The [migration inventory](doc/modal-effects-design.md#d7-session-migration-inventory)
assigns XML/location-dependent examples to D7d3 after their prerequisites.
Review, test and commit each milestone before the next. Pause after D7 is
complete, before starting D8, as requested on 7 November 2026. Both D6 choices
are confirmed.
