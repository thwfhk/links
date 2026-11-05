# Modal effects in Links

## Goal and scope

Implement modal effect types in Links on the `modal-effects` branch.
The implementation should accept and reject programs according to the
agreed typing rules and run the accepted examples with their expected
results.

Database support, control-flow linearity, and session failure are out
of scope for now. Follow `AGENTS.md` for repository conventions and
build and test commands.

## Current status

Environment preparation is complete. The next task is the design
comparison in milestone 1. The typing rules, inference approach, and
surface syntax for this branch remain to be agreed.

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

Ask the user about choices that change the typing rules or project
scope. Resolve routine code organisation within the agreed design.

## Milestones

### 1. Design comparison

Read the sources listed in the design document and trace the relevant
Links compiler passes. Write the comparison in that document, connecting
the chosen typing and inference rules to the Links implementation.
Identify reusable code, required changes, and remaining questions.

Complete when the user has agreed the initial design and scope, and
the design document contains a small set of accepted and rejected example
programs with expected types, results, or errors. Choose the first
example and divide its implementation into concrete tasks.

### 2. First working example

Implement the smallest agreed example through parsing, type checking,
compilation, and execution. Add a rejected example that exercises the
same typing rule. Include type printing needed to inspect the result.

Complete when the accepted example has the expected type and result,
the rejected example fails for the intended reason, the compiler
builds, and the affected existing tests pass. Record the tests and
implementation commit here.

### 3. Core modal effects

Extend the first implementation to cover the remaining agreed modal
constructs and typing rules. Split this milestone into tasks by rule
or observable behaviour after milestone 1 establishes the design.

Complete when each agreed rule has relevant acceptance and rejection
tests, the accepted examples run as expected, and no core design
question remains unresolved. Record any deliberate differences from
the reference implementations.

### 4. Integration and review

Test the agreed interactions with existing Links features. Check
polymorphism and the other features selected in milestone 1, error
messages, and compilation of the accepted examples. Add concise
documentation and runnable examples for the implemented syntax.

Complete when the agreed examples and relevant existing suites pass,
and a review against the chosen typing rules has resolved outstanding
implementation defects. Record completed behaviour and deferred work.

## Progress

- [x] Prepare the OCaml environment and build Links.
- [x] Run the initial handler, effect syntax, and OCaml unit tests.
- [x] Add the implementation plan and design document.
- [ ] Compare the thesis, reference implementations, and Links.
- [ ] Agree the design, examples, and initial scope.
- [ ] Implement and test the first working example.
- [ ] Implement and test the remaining core rules.
- [ ] Complete integration tests, documentation, and review.

## Working procedure

- Start each implementation task by reading `AGENTS.md`, this plan,
  the design document, and the relevant source files. Keep one chat
  editing the compiler at a time.
- Give each task a concrete expected behaviour and completion check.
  Build and run the affected tests using the commands in `AGENTS.md`.
- Review expected types and rejection cases against the agreed rules.
  Record any intended changes to existing test expectations.
- Keep each change small enough to review. When committing, group a
  coherent implementation change with its tests.
- After each task, update progress, decisions, test results, remaining
  problems, and the next action here. Record the commit when available.
- Mark a task complete only when its stated checks pass. For partial
  work, state what works and what remains. Record failures with the
  failing command and a short description.

## Decisions

- 5 November 2026: Work on `modal-effects`; database support,
  control-flow linearity, and session failure remain outside scope,
  as requested by the user.
- No modal typing or inference design has been selected yet.

## Next action

Carry out milestone 1's source comparison and propose the initial
design, example programs, and implementation tasks for review.
