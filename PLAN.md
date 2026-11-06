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

Paused after D4i as requested. The list-parentheses correction and D4f2--D4i
are complete, reviewed, tested and committed. Await the user's instruction
to resume before D4j.

- D1--D3d provide row/modality operations, shared modal types, surface syntax,
  and effect/operation resolution. D4a--D4f1 provide kind checks, persistent
  contexts, checked assignment, shared-type scope exit/export, skeleton
  conversion, root substitution and quantifier opening.
- The production batch and REPL frontends still call `TypeSugar.Check` and
  the legacy desugaring passes. Modal source programs cannot yet run through
  Fresco. New syntax is parsed and tested through separate entry points;
  the legacy frontend rejects modal constructs.
- D4f2--D4i add skeleton expansion/scope exit preserving ghosts, flexible
  requirement refinement, contextual recursive operations, consistency,
  guessing and monotype unification.
- Subtyping, constraint solving, annotation elaboration and source inference
  remain. Runtime integration and migration also remain.
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
| D4i | Persistent monotype unification, consistency and guessing | This commit |

Each completed change was reviewed and checked. Earlier verification logs and
resolved review findings remain in Git history; retain the latest integrated
results here. The D3f list-parentheses correction is complete.

## Remaining work

All tasks below are incomplete. Detailed language requirements are in the
specification; representations and algorithms are in the design. Each task
also requires the affected build/tests and review described in AGENTS.md.

| Task | Depends on | Completion check |
|---|---|---|
| D4j: subtyping, constraints and `look` | D4i | Preserve supplied polymorphic/modal structure and kind/scope requirements; failed alternatives retain no assignments |
| D4k: contextual annotation/declaration elaboration | D3e--D3f, D4 checking/refinement/recursive operations | Source annotations and closed signatures reach the contextual kind checker with positioned errors |
| D5: pure Fresco source inference | D3, D4i--D4k, required IR/export support | Adapted Fresco examples typecheck or reject as specified; a pure example evaluates; top-level unknowns and REPL failure handling work |
| D6: modal source inference and handlers | D3e--D3f, D4j--D4k, D5 | A handled operation evaluates to `42`; infer omitted handler arguments (including unused parameters); repeated rows, modal access/refinement, complete groups and polymorphism checks pass |
| D7: Links integration and migration | D5--D6 | Syntax/primitive inventory is covered; batch, REPL and typed rechecks use Fresco; programs migrate and old effect syntax rejects |
| D8: backends, documentation and final review | D7 | Interpreter/JS deep-handler checks, migration guide and selected suites pass; in-scope legacy effect inference is removed |

D4k can proceed alongside the final solver work once its own dependencies are
ready. D5 requires type-annotation elaboration; D6 also requires effect-signature
elaboration. D4j contains mutually dependent rules and may use smaller commits
for independently testable operations.

D5 uses local signed recursion for pure tests. D6 checks global signatures
with absolute modalities. Introduce a small contextual source entry point for
D5/D6 before switching the default frontend in D7. Include IR/backend support
when those first examples need it; D8 performs the final audit.

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

D4a2 updates the classifier and D4g supplies refinement. Signature elaboration
and modal integration tests must cover the remaining choices.

## Latest task and verification

6 November 2026, D4i, this commit (base `d12f864a`): persistent consistency,
guessing and monotype unification cover ghosts, quantified/modal structure,
structural rows and presences, authored recursion, kind refinement and failure
rollback. Inputs are checked before aliases are removed. Captured recursive
scopes, freshness, session requirements and later assignments have regression
coverage. The distinct unresolved-recursion error also covers growing joins
that cannot construct a result.

Independent review and integration review resolved captured-binder/shadowing
errors, stale row-duality context, discarded alias requirements, recursive
mismatch termination, fresh-ID collisions and repeated closure work. No review
findings remain. All D4i checks below ran after writer readiness, fixes and
combined-change inspection. Earlier checks retain their last tested milestones:
Correction is `02f79356`, D3f is `aa9358e4`.

| Check | Revision | Result |
|---|---|---|
| `make no-db` | D4i | Passed |
| `tests/handlers.tests` | D4i | 95 passed |
| `tests/effect_sugar.tests` | D4i | 44 passed |
| `tests/polymorphism.tests` | D4i | 55 passed |
| `tests/typecheck_examples.tests` | D4i | 167 passed, 15 ignored by existing settings |
| `tests/type_print.tests` | Correction | 10 passed |
| `tests/desugar_datatypes.tests` | Correction | 44 passed |
| `tests/modules.tests` | D3f | 41 passed |
| `tests/mutual.tests` | D3f | 17 passed |
| `tests/collections.tests` | Correction | 37 passed |
| `tests/library.tests` | D3f | 4 passed |
| `tests/freezeml.tests` | D4i | 59 passed |
| `tests/typed_ir.tests` | D4i | 26 passed |
| `tests/binaryTrees.tests` | D3f | 5 passed |
| `tests/cliArgs.tests` | D3f | 7 passed |
| `tests/operators.tests` | D3f | 21 passed |
| `tests/roundtrippable_types.tests` | D3f | 5 passed |
| `tests/strings.tests` | D3f | 5 passed |
| `tests/xml.tests` | D3f | 74 passed |
| `tests/bindings.tests` | D3f | 25 passed |
| `tests/conditionals.tests` | D3f | 6 passed |
| `opam exec -- ./run-tests nodb-unit-tests` | D4i | 871 passed |
| Menhir conflict check | Correction | Zero conflicts before and after the grammar change |
| Parse-only source and expected-type comparison | D3f | No unexpected parse regressions; 1,374 programs and 838 type strings parse |
| `make rule-check` | D4i | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual added-line tab/trailing-whitespace check | D4i | Passed |
| `git diff --check` | D4i | Passed |

D3f's parse-only audit covered excluded-feature fixtures without executing
those suites. Existing invalid examples and deliberate rejection cases remain.
Handler argument inference follows in D6; D3f preserves omission in the AST.

## Design review at the D4i pause

The marked implementation choices require no further user decision. The user
approved an error for unresolved recursive comparison. D4j must check the two
unsupported session duality cases against current Links and preserve its
accepted programs before source migration; see the
[design](doc/modal-effects-design.md#consistency-guessing-and-monotype-unification).

## Next action

Await the user's instruction to resume. Then implement subtyping, constraints
and `look`, including the remaining session duality compatibility checks before
source integration.
