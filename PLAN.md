# Modal effects in Links

## Goal and document roles

Implement modal effect types with scoped rows of named effects and use Fresco
as Links' default inference engine on `modal-effects`. Retain the legacy frontend
as an explicit option.

This file owns high-level progress, dependencies, completion checks,
verification results and the next action. [The specification](doc/modal-effects-spec.md)
owns language behaviour. [The design](doc/modal-effects-design.md) owns concrete
implementation decisions, reasons, internal invariants and source comparisons.
[AGENTS.md](AGENTS.md) owns working procedures and build/test commands.

## Current status

All in-scope D1–D7 work is complete, independently reviewed, checked and committed.
The D7 migration inventory was checked against current source on 8 November 2026.
D8a and D8b resumed on 8 November 2026 from `3a170073`. D8a1 and D8a2 are
complete; D8a3 is complete and D8b is next.

Fresco is the default for batch, REPL and compilation. Handler execution uses
`enable_handlers`. Explicit `--set=fresco=false` retains legacy compatibility;
type errors do not trigger fallback. Legacy results are counted separately from
Fresco migration. Nested list element types require parentheses in the parser
and both type printers.

Migration preserves behaviour, polymorphic contracts, feature settings and
negative rejection causes. Ordinary linear-function inference is unchanged;
sources use annotations or intermediate bindings where needed. Interfaces needing
effect variables and other excluded work remain [postponed](#postponed-work).

## Completed work

| Task | Result and completion checks | Commit |
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
| D7a | Contextual first-order primitives and recursive primitive aliases. Explicit contextual signatures cover pure/external primitives; source execution and modal rejection checks pass; remaining primitive categories are inventoried | `1f7ff34e` |
| D7b1 | Sections, negative patterns and record updates. Projection/minus sections, negative patterns and record updates check and execute | `4fad3532` |
| D7b2a | Regex syntax, splices, matching and replacement. Regex literals, splices and matching operations check and execute | `db0d3a75` |
| D7b2b | Ranges, list comprehensions, filters and ordering. List generators check and execute with existing evaluation order | `72e47dbc` |
| D7b3 | Escape continuations and contextual capture checks. Escape typing, ordinary usage and execution match existing Links behaviour | `f09237bd` |
| D7b4a0 | Callback statement skeletons and frozen module names. Callback statement skeletons preserve effects; frozen module names resolve with scope | `8cfe88a3` |
| D7b4a | Signed collection prelude with contextual callbacks. Signed collection helpers through `replicate` retain polymorphism, callback effects and ordinary usage | `0b2c0d3f` |
| D7b4b | Function, tuple, list and string helpers; inferred linear-call requirement. Helpers through `unwords` migrate; specialised curry contract is recorded separately | `efc1bca2` |
| D7b4c | Maybe, numeric, association and string-check helpers. Maybe, numeric, association and string checks migrate | `4e009da6` |
| D7c1a | Contextual Process, core actor primitives and ordinary spawn/receive. `Process(a)`, Send/self/recv and ordinary spawn/receive check and execute with isolated mailboxes | `ef94a794` |
| D7c1b | Actor locations/variants, mailbox polling and spawnWait. Locations, angel/client variants, haveMail and spawnWait check and execute on supported runtimes | `b6902b96` |
| D7c1b1 | Bound type variables and argument positions in modal subtyping. Explicit modal-forall expressions passed to signed callers retain bound type variables through export | `1822df37` |
| D7c1c | Full message suite and actor cases in mixed suites. Full messages suite and actor use sites migrate with existing feature settings | `75072fad` |
| D7c2a | Session primitives, absolute messages and generic dual consistency. Access points, send/receive/link/close execute; payload kinds, duality and ordinary usage checks pass | `2fc7f620` |
| D7c2b | Selection/offer inference, execution and contextual IR checks. Continuation-changing selection and offer execute with typed IR; branch/session/result checks pass | `ceac5dce` |
| D7c2c1 | Split-end aliases and synchronisation helpers. EndBang/EndQuery, wait/closeBang/makeEndBang/linkSync have contextual signatures and execute | `45ffa14b` |
| D7c2c2 | Callback session helpers and nested protocol skeleton duality. Fork/connection helpers execute with explicit spawned-callback contracts and no session-failure support | `0c46c06b` |
| D7c2d | CP checking, composition, linking and focused example migration. All CP forms check/lower; composition, capture and linking examples execute | `568b9db3` |
| D7c2e1 | Ordinary session suite and module/polymorphic session cases. Ordinary session suite and module/polymorphism cases retain their settings and intended checks | `79c2d173` |
| D7c2e2 | Curried modal/quantified results and ordinary session examples. Curried modal/polymorphic results check; finite calculator, split-end and channel examples migrate and execute | `fe1586af` |
| D7c2e3a | Recursive/encoded protocols and staged linear-list modules. Calculators, ATM, encoded choice and linear-list helpers typecheck; local executions and generic controls pass | `f91695f5` |
| D7c2e3b | Generic protocol examples and raw recursive runtime bindings. State, process encoding, authentication and recursive duality examples typecheck; terminating cases execute | `8b27a80b` |
| D7d3a | Remaining list, ASCII and date helpers. Existing ordering, callback effects and pure/Wild contracts pass source execution checks | `27a0b58f` |
| D7d3b | Ordinary helper interfaces and linear variant aliases. Remaining list/Maybe helpers, aliases and composition interfaces have explicit contracts and source checks | `23c0b7ba` |
| D7d3c | Binary trees and parameter-dependent recursive value kinds. Comparator and binary-tree modules migrate; existing operations and contextual callbacks execute | `48986cb7` |
| D7d3d0 | Empty switches with mode-directed results and existing partial-match behaviour. Empty-variant uses and legacy partial-match behaviour check/lower with preserved result and usage rules | `160598c6` |
| D7d3d1 | Switch-function source migration and execution controls. Named, anonymous and nested switch functions execute; recursion, partial matches and syntax errors retain their checks | `7468a1e4` |
| D7d3d2 | Church numerals and recursive bit-list examples. First-class polymorphism and recursive callback examples check and execute bounded results | `d7ef09de` |
| D7d3d3a | Safe explicit width upcasts in source and contextual IR. Explicit variant widening and record narrowing retain source checks, payload types, row requirements and typed-IR validation | `ed822373` |
| D7d3d3b | Extensible cases with checked row and callback contracts. Open-variant rows, negative patterns and upcasts check and execute | `c3f1e695` |
| D7d3e1 | Buffered channels with checked message and helper contracts. Generic queues retain FIFO order, waiting readers and payload requirements through actual execution | `b37fb1ce` |
| D7e1 | Separate checked preparation and strict typed-lowering rechecks. Separate checking/lowering from evaluation; contextual lowering rechecks validate annotations and result types | `bec9d4f9` |
| D7e2a | Persistent fixities and file preprocessing. Operator fixities survive successful inputs and file preprocessing matches string input | `1f535e58` |
| D7e2b | Canonical contextual prelude and custom batch bootstrap. Canonical prelude loading and custom/empty preludes work through Fresco | `539bcd4d` |
| D7e3a | Contextual REPL definitions, environments, loading and recovery. Definitions, loading and environments use persistent contextual state with failure recovery | `605f0454` |
| D7e3b | Contextual type search with isolated candidate checks. Type queries elaborate and match through isolated contextual inference without changing live state | `b6fddccc` |
| D7e4 | Contextual JavaScript compilation without source evaluation. Existing compile options consume contextual IR without evaluating the source program | `32df0483` |
| D7e5a0 | Shared parameter annotation scopes and trusted rigid IR declarations. Named type, row and presence variables share the intended parameter/body scope; annotations elaborate once and preserve scope-exit checks | `debb83cc` |
| D7e5 | Default Fresco frontend and explicit legacy compatibility. Fresco is the default; functional/modal source checks and no-selector batch/REPL/compile checks pass; old effect syntax rejects; compatibility routes are explicit | `8c8d1087` |
| D7 migration 1 | Identity/list handlers, operation sugar, exceptions and binary choice | `dcbb7a9d` |
| D7 migration 2 | Identity/number games and standalone handler parameters | `234683de` |
| D7 migration 3 | Operation/return/resumption patterns, direct state and U2 search | `b7f32a3b` |
| D7 migration 4 | Direct handler signatures, escaped continuations and generic local state | `b43efa52` |
| D7 migration 5 | Shared recursive declaration snapshots and generic Coop | `871cfdbc` |
| D7 migration 6 | Remaining handler-example contracts checked; Lambda/Pi deferrals recorded | `1f4594ab` |
| D7 migration 7 | Record absence checks, record remainders and records/patterns migration | `3e0248d8` |
| D7 migration 8 | Functions, closure/scope fixtures and modules | `2ab54255` |
| D7 migration 9 | Polymorphism and recursive continuation contracts | `c71fcc6f` |
| D7 migration 10 | Staged Freezeml helpers and supported typed-IR fixtures | `a80a1021` |
| D7 migration 11 | Seven ordinary AIPL examples and final in-scope integration | `c320fd80` |
| D8a1 | Pi recursive closure IR comparison and source migration. Binder scopes, general stream contracts and existing execution pass | `c284c2d4` |
| D8a2 | Interpreter close/link transfer after peer closure. Both frontends, FIFO, aliases, relays and original fusegg execution pass | `7dd4d2ce` |
| D8a3 | Bundled JavaScript startup order and actual handler execution. 44 strict paired executions, shallow controls and runtime compatibility pass | This milestone |

Each completed change was reviewed and checked. Earlier verification logs and
resolved review findings remain in Git history. The original migration inventory
and its review are `/tmp/links-d7e5-inventory.md` and
`/tmp/links-d7e5-inventory-review-summary.log`; final accounting is
`/tmp/links-d7-m11-review.md`.

## Remaining work

D8 proceeds in the milestones below. Complete, independently review, check and
commit each milestone before starting the next, following [AGENTS.md](AGENTS.md).
The main agent owns integration and progress records. Reproduce both recorded
failures first; separate source elaboration, lowering, annotations and shared
passes from runtime faults. Modal types remain erased before execution.

1. D8a1 complete: repaired Pi's post-closure IR comparison and migrated its
   source, preserving general stream contracts and execution.
2. D8a2 complete: repaired interpreter close/link transfer and checked both
   frontends, queue lifecycle and existing session execution.
3. D8a3 complete: executed deep handlers on both runtimes, covering nesting,
   repeated identities, parameters and closures; retained interpreter shallow
   execution and JavaScript shallow rejection.
4. D8b: review type metadata and recursive types through shared passes, complete
   migration documentation, and run frontend-selection and selected checks.

Both saved failures reproduce at `3a170073`. Pi's post-closure IR comparison
and source migration are complete; see [shared type contracts](doc/modal-effects-design.md#shared-type-and-traversal-contracts).
The close/link repair is complete; see [session integration](doc/modal-effects-design.md#d7-session-integration).
D8a3 repaired standalone JavaScript startup order and passed the actual
interpreter/JavaScript execution matrix. The next action is D8b's shared-pass
metadata review, migration documentation and final selected checks after
committing D8a3.

| Task | Depends on | Completion checks |
|---|---|---|
| D8a: backend execution | D7 | Complete: actual interpreter and JavaScript handler matrix, Pi IR repair and close/link repair are reviewed and checked. See completed milestones above. |
| D8b: frontend options, documentation and final review | D8a | Both frontends remain available through the existing Fresco setting, with Fresco as the default and no automatic fallback. Check frontend selection in batch, REPL and compilation; review ghosts, exported variable requirements, recursive type consumers, lowering, optimisation and both backends; the migration guide and selected suites pass. |

Pi and close/link failures are resolved by D8a1/D8a2. Their causes and repairs
are recorded in [shared type contracts](doc/modal-effects-design.md#shared-type-and-traversal-contracts)
and [session integration](doc/modal-effects-design.md#d7-session-integration).

Retain the design's reference Fresco pairs and `tests/freezeml.tests`. Check
inferred type structure, higher-rank fields, zero/n-ary functions, explicit type
operations, signed recursion, and successful and failed interactive definitions.

Retain deep/shallow handlers, handler parameters, qualified identities, repeated
effects, omitted handler annotations/type arguments, explicit modal or
polymorphic effect arguments, and `Any`-to-`Abs` refinement through lock access.
Keep records/variants, patterns, lists/tuples, modules, actors and existing
sessions covered, including `tests/messages.tests`, with their typed-IR,
rechecking and other feature settings unchanged.

Retain both inference frontends. `--fresco` selects Fresco explicitly;
`--set=fresco=false` selects the legacy frontend. D8 does not require deleting
legacy inference. Keep compatibility checks separate from Fresco coverage.
General contracts needing independent effects stay postponed; specialised uses
do not establish preservation of those contracts. Keep all excluded features
outside D8.

## Postponed work

The user deferred sockets, XML/forms and FFI/function locations on 7 November
2026, and separately deferred the console example. Their identifiers and checks
are retained below. These items and their dependent library/example migrations
are outside the current D7/D8 scope and require separate scheduling.

| Item | Reason or completion checks when resumed |
|---|---|
| D7c2e3c: socket examples | SMTP/IRC models typecheck; local dummy execution passes. |
| D7d1: XML and forms | XML, form/page constructs and their prelude dependencies check and execute. Formlet State helpers retain their existing capture contract. |
| D7d2: FFI and function locations | Foreign declarations, locations and FFI dependencies survive checking and lowering. |
| D7d3e2: console example | Console helpers and finite actor games retain their callback contracts and results; deferred by the user as peripheral to modal effects. |
| General interfaces needing independent effect variables | Preserve the original contracts and compatibility routes. Do not specialise or redesign them to pass migration, or add effect-variable support. See the [contract inventory](doc/modal-effects-design.md#signatures-with-independent-effect-variables), including the two-thunk test, `wait`, MVU, `curry` and Lambda's `lit`. |
| Database support, control-flow linearity, session failure and higher-order effects | Outside the agreed scope; retain their exclusions and dependent fixtures. See [specification scope](doc/modal-effects-spec.md#1-scope). |
| Excluded consumers, retained protocol/list modules and existing ignored examples | Preserve recorded boundaries, ignore reasons and feature settings. See the [migration inventory](doc/modal-effects-design.md#d7-session-migration-inventory) and [final accounting](doc/modal-effects-design.md#handler-migration-and-modal-examples). |
| Recursive-row inference and unresolved row/presence duality | Retain the current occurs check and compatibility limits. See [consistency](doc/modal-effects-design.md#consistency-guessing-and-monotype-unification). |
| Raw-mu strict-lowering follow-up | Named recursive declarations preserve the migrated protocols; raw-mu expansion can exceed the check bound or overflow. See the [recorded evidence](doc/modal-effects-design.md#handler-migration-and-modal-examples). |
| Solved-tail linear dot-projection follow-up | Record-pattern extraction works; selecting a linear field through a solved row tail can leave it in the discarded-row check. See [record checks](doc/modal-effects-design.md#d7-sections-patterns-and-record-updates). |
| Legacy strict handler IR checking | Additional direct/signed legacy probes fail on operation-row entries. Existing compatibility settings retain execution; keep this checker repair separate from Fresco migration. See [frontend integration](doc/modal-effects-design.md#d7-frontend-integration-plan). |
| Source names for later-result forall binders and inferred free-variable kind displays | Retain these annotation/display follow-ups; stored ordinary-kind requirements remain checked. See [annotation scopes](doc/modal-effects-design.md#contextual-annotation-and-declaration-elaboration). |

Questions arising solely from excluded examples or unsupported contracts are
outside the current discussion. Keep all retained legacy runs as explicit
compatibility checks. Formlet State details are in the
[ordinary library design](doc/modal-effects-design.md#d7-ordinary-library-inventory).

## Recorded decisions

The user decisions of 6--7 November 2026 are recorded in the specification
and design:

- [Language rules and reference choices](doc/modal-effects-design.md#language-decisions-and-their-reasons).
- [Effect matching order](doc/modal-effects-design.md#parameterised-effect-matching-order).
- [Linearity, global signatures and initial effects](doc/modal-effects-design.md#value-linearity-and-legacy-effect-sugar).
- [D4 ghost kinds and instantiation checks](doc/modal-effects-design.md#subtyping-and-instantiation-information).
- [D4k signature binders and ordinary row arguments](doc/modal-effects-design.md#contextual-annotation-and-declaration-elaboration).

The user confirmed both D6 choices on 7 November 2026: handler result inference
from return clauses and source-only modal checks. See the
[scoped-effects design](doc/modal-effects-design.md#d6-scoped-effects-in-ir).

On 8 November 2026, the user confirmed retaining the legacy frontend as an
option after D8. See [frontend selection](doc/modal-effects-spec.md#9-initial-effect-context).

### D7 choices awaiting review

The marked choices remain implementation decisions for review. Their current
behaviour passes the completed D7 checks.

1. Actor and session contracts: `spawnWait` body/result kinds, absolute message
   payloads, spawned callback modalities and `Wild` for selection/offer.
   See [actors](doc/modal-effects-design.md#d7-actor-integration) and
   [sessions](doc/modal-effects-design.md#d7-session-integration).
2. Encoded-choice message modalities and staged linear-list modules.
   See [session migration](doc/modal-effects-design.md#d7-session-migration-inventory).
3. Continuation access across changes of effect context.
   See [continuations](doc/modal-effects-design.md#d7-continuations).
4. Typed-lowering rechecks, default/custom prelude preparation, contextual type
   search and compile input/output ordering.
   See [frontend integration](doc/modal-effects-design.md#d7-frontend-integration-plan).
5. Shared parameter annotation names. Later-result forall source names remain
   in [postponed work](#postponed-work). See
   [annotation scopes](doc/modal-effects-design.md#contextual-annotation-and-declaration-elaboration).

## Latest task and verification

8 November 2026, D8a3: repaired standalone JavaScript runtime inclusion order.
The standard runtime initialises before handler continuation bindings; custom
runtime order and standalone script mode remain unchanged. No runtime algorithms
or modal runtime values were added. Independent review passed:
`/tmp/links-d8a3-final-review.md`.

Tested source: `7dd4d2ce` plus the patch and source hashes in
`/tmp/links-d8a3-verification/`. Source hashes stayed unchanged during checks.
Full commands/results are in `results.json`; full logs retain all source and
Node commands. Core and unit sources are unchanged from D8a2's 1,539 unit checks.

| Command | Result | Log |
|---|---|---|
| `make no-db` | Passed | `build.log` |
| `python3 tests/fresco_backend.py` | 44 strict paired interpreter/Node Fresco executions; 4 interpreter shallow executions and 4 JavaScript shallow rejections; 4 separate ordinary/legacy/custom runtime controls passed | `backend.log` |
| `python3 tests/fresco_compile.py`; `python3 tests/fresco_repl.py` | 10 compile and 11 REPL scenarios passed | `compile.log`, `repl.log` |
| `./test-harness tests/<suite>.tests`: handlers, effect_sugar, fresco_modal, fresco_default, fresco_batch | 119 Fresco and 71 compatibility passed; 0 ignores | Per-suite `.log` files |
| `make rule-check`; `git diff --check` | Passed; GNU-find tab check skipped, formatter disabled | `rule-check.log`, `diff-check.log` |

Logs are in `/tmp/links-d8a3-verification/`. The additional strict legacy-handler
IR failure remains separately recorded under postponed work; the existing legacy
compatibility setting passes actual handler execution. D8b remains. All earlier
postponed work and the five D7 choices awaiting user review remain unchanged.
