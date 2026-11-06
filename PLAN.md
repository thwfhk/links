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

D3e, D3f and D4a2 are complete. Implementation is paused at the user's
request before D4f2; D4f2 has not been started.

- D1--D3d provide row/modality operations, shared modal types, surface syntax,
  and effect/operation resolution. D4a--D4f1 provide kind checks, persistent
  contexts, checked assignment, shared-type scope exit/export, skeleton
  conversion, root substitution and quantifier opening.
- The production batch and REPL frontends still call `TypeSugar.Check` and
  the legacy desugaring passes. Modal source programs cannot yet run through
  Fresco. New syntax is parsed and tested through separate entry points;
  the legacy frontend rejects modal constructs.
- Skeleton solution expansion, scope exit preserving ghosts, kind refinement,
  consistency, subtyping, constraint solving and source inference remain.
  Annotation elaboration, runtime integration and migration also remain.
- D3e removes higher-order effect flags, syntax and row rules. Ordinary
  operation arguments and results must be absolute.
- D3f implements `List A`, combined kind annotations and angle-bracket
  handled-effect annotations, for example `handle <Reader> (...)`.
- D4a2 implements the thesis' quantified-type classification while retaining
  declared binder requirements. Modal-kind refinement remains in D4g.

The requested scope correction, syntax migration and classification update
are complete. No unresolved decisions remain for these three milestones.
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
| D4a2 | Thesis quantified-type classification | This commit |

Each completed change was reviewed and checked. Earlier verification logs and
resolved review findings remain in Git history; retain the latest integrated
results here. The D1--D3 scope and syntax corrections are complete.

## Remaining work

All tasks below are incomplete. Detailed language requirements are in the
specification; representations and algorithms are in the design. Each task
also requires the affected build/tests and review described in AGENTS.md.

| Task | Depends on | Completion check |
|---|---|---|
| D4f2: skeleton solution expansion and scope exit | D4f1, D4d1 | Preserve ghosts, scope, live unknowns and recursive sharing; reject escapes without changing the input context |
| D4g: ordinary/modal requirement refinement | D4f2, D4c, D4a2 | Enforce flexible `Abs` and structural payload requirements through later assignment, scope exit and export; never narrow rigid binders |
| D4h: contextual recursive type operations | D4g | Alias application, unfolding and comparison preserve binders and terminate on tested equal/unequal recursive applications with changing arguments |
| D4i: monotype unification, consistency and guessing | D4f2--D4h | Adapt existing Links structural unification to checked Fresco assignment; cover ghosts, supplied polymorphic fields, kinds/scope, repeated rows and failed alternatives |
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

D4a2 updates the classifier. Refinement, signature elaboration and modal
integration tests must cover the remaining choices.

## Latest task and verification

6 November 2026, D4a2, this commit (base `aa9358e4`): quantified value-type
binders have temporary `Abs` summaries during modal classification. Declared
ordinary and modal kinds still govern well-formedness and type argument checks.
Independent review found no compiler or test issues; a documentation wording
finding was corrected.

The table retains the latest result for each check. D4a2 checks ran on the
final integrated source; D3f results refer to `aa9358e4`.

| Check | Revision | Result |
|---|---|---|
| `make no-db` | D4a2 | Passed |
| `tests/handlers.tests` | D4a2 | 95 passed |
| `tests/effect_sugar.tests` | D4a2 | 44 passed |
| `tests/polymorphism.tests` | D4a2 | 55 passed |
| `tests/typecheck_examples.tests` | D4a2 | 167 passed, 15 ignored by existing settings |
| `tests/type_print.tests` | D3f | 10 passed |
| `tests/desugar_datatypes.tests` | D3f | 42 passed |
| `tests/modules.tests` | D3f | 41 passed |
| `tests/mutual.tests` | D3f | 17 passed |
| `tests/collections.tests` | D3f | 37 passed |
| `tests/library.tests` | D3f | 4 passed |
| `tests/freezeml.tests` | D3f | 59 passed |
| `tests/typed_ir.tests` | D3f | 26 passed |
| `tests/binaryTrees.tests` | D3f | 5 passed |
| `tests/cliArgs.tests` | D3f | 7 passed |
| `tests/operators.tests` | D3f | 21 passed |
| `tests/roundtrippable_types.tests` | D3f | 5 passed |
| `tests/strings.tests` | D3f | 5 passed |
| `tests/xml.tests` | D3f | 74 passed |
| `tests/bindings.tests` | D3f | 25 passed |
| `tests/conditionals.tests` | D3f | 6 passed |
| `opam exec -- ./run-tests nodb-unit-tests` | D4a2 | 675 passed |
| Menhir conflict check | D3f | Zero conflicts before and after the grammar change |
| Parse-only source and expected-type comparison | D3f | No unexpected parse regressions; 1,374 programs and 838 type strings parse |
| `make rule-check` | D4a2 | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual added-line tab/trailing-whitespace check | D4a2 | Passed |
| `git diff --check` | D4a2 | Passed |

D3f's parse-only audit covered excluded-feature fixtures without executing
those suites. Existing invalid examples and deliberate rejection cases remain.
Handler argument inference follows in D6; D3f preserves omission in the AST.

## Latest documentation task

6 November 2026: recorded reuse of Links' monotype unification and kind-inference
ideas, combined kind syntax, optional handlers with inferred effect arguments,
and existing signatures needing independent effect variables. Clarified ambient-
effect wording in the specification. Updated D3f, D4i and integration coverage.

Verification: inspected compiler code, reference rules and existing examples;
checked document consistency, links and whitespace. `git diff --check` passed.
No compiler changes, build or tests.

## Next action

Remain paused before D4f2. On explicit resumption, implement skeleton solution
expansion and scope exit, preserving ghosts, scope, live unknowns and recursive
sharing. D5 still requires its contextual annotation and solver dependencies.
