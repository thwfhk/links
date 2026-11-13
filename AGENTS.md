# AGENTS.md

Links is a functional programming language. This repository contains
its compiler, interpreter, runtimes, and libraries, written mainly in
OCaml.

## Repository shape

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


## Task management

For each independent task `X` that spans sessions or needs a handover,
keep one `tasks/X/PLAN.md`. Record milestones, completed and remaining
work, dependencies, completion checks, and the latest check results.
At each pause or handover, record the next action and any blockers.
Mark the plan complete when its completion checks pass.

Use `tasks/X/SPEC.md` for changes to language behaviour. Use
`tasks/X/IMPL.md` for significant implementation decisions. Mark design
questions that need the user's review. Once resolved, replace each
question with the decision.

Link between these documents without repeating their contents.

## Working procedure

- Before an implementation task, read the relevant documents first.
- Follow existing Links conventions for routine choices. Ask the user
  before making unresolved choices that affect which programs Links
  accepts, what annotations it requires, or how programs run.
- Use Sol 6.1 x-high subagents by default for design, coding,
  investigation and review. Use Sol 6.1 high for simpler tasks, and
  Sol 6.1 max for very difficult tasks. Use Astra only for an
  extremely challenging task after earlier attempts have failed
  several times. Continue directly when delegation is unavailable.
- Give each agent a bounded task, relevant sources, allowed files and
  completion checks. Delegate independent work in parallel. Keep one
  writer per file; use separate worktrees when edits would overlap.
  The main agent owns integration, final verification and progress records.
- Save full build/test output in log files instead of sending them in
  agent messages. Agent messages should summarise findings and
  reference source locations or logs; copy only the excerpts needed to
  explain a finding.
- When waiting for another agent and no useful independent work remains,
  use the wait tool and resume when results arrive.
- Avoid repeating the full build and regression suite in every
  worktree for an unchanged revision.
- Independently review substantial compiler changes. Resolve review
  findings before running the required checks on the final combined
  changes.


## References

Consult these references only when the user explicitly asks and they
are available.

- Wenhao's thesis is in the repo `~/code/latex/phd-thesis`. It
  contains both modal effects and Fresco type inference.
- Wenhao's homepage is `thwfhk.github.io`.
- Wenhao's paper on control-flow linearity is in the repo
  `~/code/algebraic-effects/linear-handlers`.
- Aghilas' implementation of modal effects together with Fresco type
  inference is in the repo
  `~/code/type/frost/paper/artifact/freso-implementation`. This is the
  main implementation reference for Fresco.
- Aghilas' implementation of modal effects with a simple DK style
  bidirectional type inference is in the repo
  `~/code/algebraic-effects/aghilas-met-impl`.

## Build and test

Run all commands from the repository root.

### 1. Build

Use OCaml 5.3.0 or later. Install the build dependencies with
`opam install ./links.opam --deps-only`. Install `ounit2` for unit tests.

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
When adding or moving an example, update its entry in
`tests/typecheck_examples.tests`.

Run OCaml unit tests when changing the code they cover:

```sh
opam exec -- ./run-tests nodb-unit-tests
```

For changes that affect database behaviour, build with the relevant
drivers (`make all`), configure a local database, and run
`make database-tests`. Run `opam exec -- ./run-tests db-unit-tests`
when changing code covered by those unit tests.

`make tests` runs all top-level regression suites, including suites
outside the current scope. Use the selected suites above for now.

### 3. Check source changes

```sh
make rule-check
git diff --check
```

For build and test results, report the command, tested source revision,
result, log path, and any relevant failure excerpts. For
documentation-only edits, check the text and whitespace.

## Code changes

- Make only changes needed for the requested outcome.
- Follow the surrounding OCaml and Links code style. Keep `.ml` and
  `.mli` files consistent. Follow the nearest `.ocamlformat` and
  avoid reformatting unrelated code.
- Use the official [OCaml Programming Guidelines](https://ocaml.org/docs/guidelines)
  for general coding style. Preserve local conventions where they differ.
- Edit lexer and parser sources (`.mll` and `.mly`), and let the build
  generate their OCaml files.
- Edit package metadata in `dune-project` and the relevant
  `.opam.template` files. Include changes to the tracked `.opam` files
  regenerated by Dune.
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
