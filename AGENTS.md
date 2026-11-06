# AGENTS.md

Links is a functional programming language. This repository contains
its compiler, interpreter, runtimes, and libraries, written mainly in
OCaml.

## Repository shape

The goal of the `modal-effects` branch is to implement modal effect
types for Links. Work on `modal-effects` unless the user requests
another branch.

Read [PLAN.md](PLAN.md) before starting work. Keep high-level progress,
dependencies, completion checks, the latest verification results and
the next action there. Record intended language behaviour in
[doc/modal-effects-spec.md](doc/modal-effects-spec.md). Keep concrete
implementation decisions, reasons, internal invariants and source
comparisons in [doc/modal-effects-design.md](doc/modal-effects-design.md).
Keep working procedures in this file. Link between these documents
without repeating their contents. Earlier task logs remain in Git history.

Database support, control-flow linearity, session failure and higher-order
effects are out of scope for now. Do not extend their implementations or
run their dedicated test suites unless the user requests it.

## Working procedure

- Before an implementation task, read the applicable specification and
  design sections and relevant source files as well as PLAN.md.
- Use Sol 6.1 High subagents by default for coding, investigation and review.
  Use Astra High for very difficult tasks. Use Astra x-high only for an
  extremely challenging task after an earlier attempt has failed; state
  the unresolved problem before escalating.
- Give each agent a bounded task, relevant sources, allowed files and
  completion checks. Delegate independent work in parallel. Keep one
  writer per file; use separate worktrees when edits would overlap.
  The main agent owns integration, final verification and progress records.
- Assign each audit to one agent with a stated scope and expected result.
  Other agents use that result. The independent reviewer checks the method,
  inspects selected cases and investigates gaps. Repeat the full audit only
  when a finding requires it.
- Choose minor language details using existing Links conventions, the
  thesis and Aghilas' implementation. Check apparent reference defects
  against the thesis and small examples. Record the choice and reason
  in the design document, and update the specification if the choice
  affects language behaviour. Ask before major choices affecting scope,
  accepted programs, required annotations or runtime behaviour.
- Keep changes small enough to review and independently review substantial
  compiler changes. Reviewers should inspect rules, likely failure cases
  and meaningful tests. Avoid repeating the full build and regression
  suite in every worktree for an unchanged revision.
- Finish edits before integrated testing. Every writer reports readiness;
  complete review fixes and inspect the combined diff before running the
  integrated checks. Record the tested source revision with the results.
  If code changes during testing, identify and rerun the affected checks.
- Run the required checks on the final integrated revision. After a review
  fix, rerun the affected checks; repeat wider checks when the change or a
  remaining concern requires them. Preserve source revisions with results.
- Add source typing and execution checks as soon as their dependencies
  permit. Internal unit-test counts do not establish source-level support.
- Resolve review findings, inspect the combined diff and commit completed
  implementation tasks with tests and progress records. Honour pauses and
  keep documentation reviews separate from resuming compiler work.

- Local worktrees should be at `.worktrees/<name>`.
- `core/` contains parsing, type checking, compiler passes, evaluation,
  and the web server. Database query compilation is in `core/query/`.
- `bin/` contains the command-line driver and REPL.
- `lib/stdlib/` and `prelude.links` contain the Links standard library.
- `lib/js/` contains the JavaScript runtime.
- `database/` contains database drivers; `lens/` contains relational
  lenses.
- `tests/` contains regression tests and OCaml unit tests.
- `examples/` contains Links programs; `doc/` contains documentation.

## References

Useful references. Refer to them when asked and when available.

- Wenhao's thesis is in the repo `~/code/latex/phd-thesis`. It
  contains both modal effects and Fresco type inference.
- Wenhao's homepage is `thwfhk.github.io`.
- Wenhao's paper on control-flow linearity is in the repo
  `~/code/algebraic-effects/linear-handlers`.
- Aghilas' implementation of modal effects together with Fresco type
  inference is in the repo
  `~/code/type/frost/paper/artifact/freso-implementation`. Use this
  one as the main reference of implementation.
- Ahilas' implementation of modal effects with a simple DK style
  bidirectional type inference is in the repo
  `~/code/algebraic-effects/aghilas-met-impl`.

## Build and test

Run all commands from the repository root.

### 1. Build

```sh
make no-db
```

This builds the compiler without database drivers and creates the
`./links` launcher. Rebuild after changing compiler code and before
running tests; the test harness uses the existing launcher and binary.

### 2. Test the affected behaviour

Run each relevant regression suite separately. For effect-handler and
effect-type changes, start with:

```sh
./test-harness tests/handlers.tests
./test-harness tests/effect_sugar.tests
```

Run other affected suites with `./test-harness tests/<suite>.tests`.
For broad typing changes, include `tests/polymorphism.tests` and
`tests/typecheck_examples.tests`. Add tests for the new behaviour to
the appropriate suite. Preserve each suite's feature settings.

Run OCaml unit tests when changing the code they cover:

```sh
opam exec -- ./run-tests nodb-unit-tests
```

`make tests` runs all top-level regression suites, including suites
outside the current scope. Use the selected suites above for now.

### 3. Check source changes

```sh
make rule-check
git diff --check
```

Report which build and tests ran, whether they passed, and any failures.
For documentation-only edits, check the text and whitespace; no
compiler build or test run is needed.

## Code changes

- Make only changes needed for the requested outcome.
- Follow the surrounding OCaml and Links code style. Keep `.ml` and
  `.mli` files consistent. `.ocamlformat` disables automatic formatting;
  avoid reformatting unrelated code.
- Use the official [OCaml Programming Guidelines](https://ocaml.org/docs/guidelines)
  for general coding style. Preserve local conventions where they differ.
- Edit lexer and parser sources (`.mll` and `.mly`), and let the build
  generate their OCaml files.
- Edit package metadata in `dune-project` and the relevant
  `.opam.template` files; Dune generates the `.opam` files.
- For syntax or type-system changes, inspect the affected syntax types,
  traversals, type checker, desugaring passes, and backends. Update the
  parts that handle the changed construct.
- Add regression tests for behaviour changes and bug fixes. For typing
  changes, cover both accepted and rejected programs. Follow existing
  `.tests` files and their configuration files.
- Keep generated build files out of source changes.

## Writing style

- Use concise, simple, and direct language. Never invent names,
  terminologies, or metaphors.
- Use British English.
- Follow local writing style. Preserve existing manual line breaks
  where possible.
