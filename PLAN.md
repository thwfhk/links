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

Implementation is paused at the user's request after D4f1. The documentation
review below does not resume compiler work.

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
- Existing code includes higher-order effect flags, syntax and row rules from
  the earlier design. D3e below removes that extension from the current scope.
- List types will use `List A`, and handled-effect annotations will use angle
  brackets, for example `handle <Reader> (...)`. D3f applies these source changes.
- Modal-kind refinement and the thesis' quantified-type classification are
  required. D4g adds refinement; D4a2 below updates the implemented classifier.

Completed compiler work ends at `7af62207`; `87264380` records the pause.
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

Each completed change was reviewed and checked. Earlier verification logs and
resolved review findings remain in Git history; retain the latest integrated
results here. D1--D3 require the scope correction below before final acceptance.

## Remaining work

All tasks below are incomplete. Detailed language requirements are in the
specification; representations and algorithms are in the design. Each task
also requires the affected build/tests and review described in AGENTS.md.

| Task | Depends on | Completion check |
|---|---|---|
| D3e: remove higher-order effect extension | D1--D3d, D4b | Reject `effect higher`; restore `higher` as an identifier; ordinary row and absolute-signature checks pass |
| D3f: list types and handler annotation syntax | D2--D3d | Parse/print `List A` and `handle <E>`/`shallowhandle <E>`; migrate signatures and fixtures; reject replaced forms; preserve XML, list expressions/patterns and type round trips |
| D4a2: thesis quantified-type classification | D4a--D4b | Classify quantified value-type binders at `Abs` without changing their declared kinds; test classification versus well-formedness/instantiation |
| D4f2: skeleton solution expansion and scope exit | D4f1, D4d1 | Preserve ghosts, scope, live unknowns and recursive sharing; reject escapes without changing the input context |
| D4g: ordinary/modal requirement refinement | D4f2, D4c, D4a2 | Enforce flexible `Abs` and structural payload requirements through later assignment, scope exit and export; never narrow rigid binders |
| D4h: contextual recursive type operations | D4g | Alias application, unfolding and comparison preserve binders and terminate on tested equal/unequal recursive applications with changing arguments |
| D4i: consistency and guessing | D4f2--D4h | Bound-variable/ghost restrictions, supplied polymorphic fields, monotype assignment and repeated-row reflexivity have positive/negative coverage |
| D4j: subtyping, constraints and `look` | D4i | Preserve supplied polymorphic/modal structure and kind/scope requirements; failed alternatives retain no assignments |
| D4k: contextual annotation/declaration elaboration | D3e--D3f, D4 checking/refinement/recursive operations | Source annotations and closed signatures reach the contextual kind checker with positioned errors |
| D5: pure Fresco source inference | D3, D4i--D4k, required IR/export support | Adapted Fresco examples typecheck or reject as specified; a pure example evaluates; top-level unknowns and REPL failure handling work |
| D6: modal source inference and handlers | D3e--D3f, D4j--D4k, D5 | A handled operation evaluates to `42`; repeated rows, modal access/refinement, complete groups and combined polymorphism checks pass |
| D7: Links integration and migration | D5--D6 | Syntax/primitive inventory is covered; batch, REPL and typed rechecks use Fresco; programs migrate and old effect syntax rejects |
| D8: backends, documentation and final review | D7 | Interpreter/JS deep-handler checks, migration guide and selected suites pass; in-scope legacy effect inference is removed |

D3f covers lexer/parser rules, type printers and parentheses, built-in type
strings, prelude/library signatures, examples, documentation and affected test
expectations. Preserve the existing internal list type and runtime representation.
Change type annotations without changing list expressions or patterns. Migrate
initialisation strings in the same buildable change that removes old list-type
syntax. Check nested/function element types, qualified/parameterised handled
effects, both handler depths, and XML/operation-pattern delimiter interactions.

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
  repeated effects and source-level `Any`-to-`Abs` refinement through lock access.
- Inventory records/variants, patterns, lists/tuples, modules, actors, XML/web
  forms, FFI and existing sessions. Include `tests/messages.tests` for mailbox
  migration and preserve typed-IR/recheck settings.
- Audit ghosts, exported variable requirements, recursive type consumers,
  lowering, optimisation and both backends. Keep excluded features outside scope.

## Decisions resolved

6 November 2026: the user resolved all six questions. The specification now
records the selected language rules; the design records their reasons and
algorithm consequences. The choices preserve ordinary linearity/CFL-disabled
behaviour, select equality before `Abs` fallback, adopt the thesis' quantified
classification, add implicit `modal []` to global signatures, start programs
with ambient context `Wild`, and reserve built-in effects from user handlers.

Implementation must update the existing classifier (D4a2) and cover these
choices in refinement, signature elaboration and modal integration tests.

## Latest task and verification

6 November 2026, D4f1, commit `7af62207`: skeleton operations and recursive
scope/copying corrections passed independent review. All findings were resolved.
The final integrated revision passed the following checks:

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
| `opam exec -- ./run-tests nodb-unit-tests` | 672 passed, including 107 new tests |
| `make rule-check` | Passed; GNU-find tab check skipped, formatter check disabled |
| Manual changed/new-file tab/trailing-whitespace check | Passed |
| `git diff --check` | Passed |

## Latest documentation task

6 November 2026: added D3f for `List A` type syntax and angle-bracket handled-effect
annotations. Updated target syntax and examples in the specification and recorded
the parser/printer/migration requirements in the design. Compiler work remains
paused.

Verification: inspected parser and type-printer paths, checked document links
and whitespace; `git diff --check` passed. No compiler changes, build or tests.

## Next action

Compiler work remains paused. On explicit resumption, complete D3e's scope
correction, D3f's syntax changes and D4a2's quantified-classification update,
then D4f2's skeleton
solution expansion and scope exit. D5 requires its contextual annotation and
solver dependencies.
