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
commits. Work is paused before D7.

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
| D6 | Modal source inference, complete handlers, inferred effect arguments and scoped IR/backend support | This commit |

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

## Decisions resolved

6 November 2026: the user resolved all six questions. The specification now
records the selected language rules; the design records their reasons and
algorithm consequences. The choices preserve ordinary linearity/CFL-disabled
behaviour, select equality before `Abs` fallback, adopt the thesis' quantified
classification, add implicit `modal []` to global signatures, start programs
with ambient context `Wild`, and reserve built-in effects from user handlers.

D4a2 updates the classifier and D4g supplies refinement. D4k tests global
signature modalities. D5/D6 check these choices through source inference.

## Latest task and verification

7 November 2026, D6, this commit (base `4f12cd67`): modal source inference
checks operations, complete handlers, omitted effect arguments, deep/shallow
resumptions, parameters, modal access, ordinary usage and supplied polymorphism.
Scoped IR evidence survives optimisation and closure conversion. Source tests
execute handled operations yielding `42`, repeated effects yielding `11`,
parameter updates, effectful `map`, returned closures and shallow resumptions.

Independent review resolved operation annotations, guarded patterns/projection,
handler result scope exit and list element requirements. No implementation
findings remain. All writers finished and the combined changes were inspected
before integrated testing. The 40 source/test hashes in
`/tmp/links-d6-verification.WRWrKy/source.sha256` match the tested revision;
checksums were rechecked after testing. Integrated logs are in that directory.
Documentation was updated afterwards without source changes.

| Check | Result |
|---|---|
| `make no-db` | Passed |
| `opam exec -- ./run-tests nodb-unit-tests` | 1,181 passed, including 87 pure source/IR, 57 modal source, 20 scoped IR and 12 modal-join cases |
| `tests/fresco.tests`, `tests/fresco_typecheck.tests`, `tests/fresco_modal.tests` | 5, 2 and 12 passed |
| `tests/handlers.tests`, `tests/effect_sugar.tests` | 95 and 44 passed |
| `tests/polymorphism.tests`, `tests/typecheck_examples.tests` | 55 and 167 passed; 15 ignored by existing settings |
| `tests/freezeml.tests`, `tests/typed_ir.tests` | 59 and 26 passed |
| `tests/collections.tests`, `tests/bindings.tests`, `tests/mutual.tests` | 37, 25 and 17 passed |
| `tests/modules.tests`, `tests/desugar_datatypes.tests` | 41 and 44 passed |
| `tests/type_print.tests`, `tests/roundtrippable_types.tests` | 10 and 5 passed |
| `tests/operators.tests`, `tests/conditionals.tests` | 21 and 6 passed |
| Optimised CLI REPL failure recovery | A failed handler leaves the declared effect and signed function available; subsequent execution yields `42` |
| JavaScript generation and `node --check` | Eight pure/modal programs passed |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual added/new-line tab/trailing-whitespace check, `git diff --check` | Passed |

The 18 regression suites total 671 successes. D5's separately reviewed commit
`4f12cd67` passed its build, 1,092 unit tests and 659 regression tests, plus
REPL recovery and four JavaScript generation/syntax probes. Its integrated
logs and matching source hashes remain in `/tmp/links-d5-verification.Q5tr7l`.
The D6 focused review snapshot is `/tmp/links-d6-source-audit.mkwflS`.
D8 retains the final JavaScript execution audit.

## Decisions for review at the D6 pause

The [D6 design](doc/modal-effects-design.md#d6-scoped-effects-in-ir) records
these choices, their reasons and alternatives:

1. Infer a handler result from its return clauses, then check operation clauses
   at that type. A wider result needs an annotation on the whole handler.
   Inferring a common result from all clause skeletons is the alternative.
2. Keep modal call/access and effect-argument kind checks in source inference
   during D6. The IR checks retained operation/handler evidence after runtime
   type erasure. Retaining further call/coercion evidence and repeating kind
   checks is the alternative; audit this boundary in D7/D8.

## Decisions and deferred work at the D4 pause

7 November 2026: the user chose `Abs` for ordinary ghosts during skeleton
inference, with full inference rechecking instantiation kinds and modal access.
The [design](doc/modal-effects-design.md#subtyping-and-instantiation-information)
records the rule, source comparison and required tests. The compiler follow-up
is complete; the verification results above cover both remaining D4 tasks.

The user approved rejecting the legacy row-duality bug that can change a
channel's protocol without changing the channel. The user also approved deferring recursive row inference accepted by
Links' `infer_recursive_types=all` and `positive` settings. Unresolved presence
duality remains an explicit error; the legacy helper asserts in this case.
Growing recursive equality retains the previously approved cannot-establish
error. These cases and the compatibility probes are recorded in the
[design](doc/modal-effects-design.md#consistency-guessing-and-monotype-unification).

### D4k compatibility choices

The [D4k design](doc/modal-effects-design.md#contextual-annotation-and-declaration-elaboration)
records two compatibility choices and their alternatives:

1. The user confirmed preserving Links' implicit named rigid Type/Row/Presence
   binders in written function signatures, without generalising unsigned
   definitions.
2. The user confirmed closing the parser's synthetic tail in ordinary braced
   Row arguments, preserving Links' behaviour with legacy effect sugar disabled.
   With both `effect_sugar` and `open_default` enabled, Links inserts an open
   tail. The contextual implementation follows the documented replacement of
   legacy effect sugar and closes this synthetic tail.

## Next action

Paused before D7. Discuss the two D6 choices above before resuming migration.
D7 switches the default frontend, completes the in-scope syntax/primitive
inventory, and migrates batch, REPL, typed rechecks and source programs.
D8 completes the backend audit, JavaScript execution checks and migration docs.
