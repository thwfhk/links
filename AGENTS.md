# AGENTS.md

SmallLinks is a native subset of Links. Its compiler and interpreter
are written mainly in OCaml. The [language guide](tasks/small/SPEC.md)
describes the language supported by this repository.

## Repository shape

- Local worktrees should be at `.worktrees/<name>`.
- `core/` contains parsing, type checking, compiler passes and evaluation.
- `bin/` contains the command-line driver and REPL.
- `prelude.links` contains the prelude loaded at startup. `lib/stdlib/`
  contains importable standard library modules.
- `tests/` contains regression suites and scripts. `tests/unit/`
  contains the OCaml IR unit tests.
- `examples/` contains SmallLinks programs. `doc/` contains the older
  Links manuals.
- `tasks/small/` contains the language guide, plan and implementation
  notes. `.github/workflows/default.yml` runs CI.


## Task management

When the user asks, for each independent large task `X` that spans
sessions or needs a handover, keep one `tasks/X/PLAN.md`. Record
milestones, completed and remaining work, dependencies, completion
checks, and the latest check results. At each pause or handover,
record the next action and any blockers. Mark the plan complete when
its completion checks pass.

Use `tasks/X/SPEC.md` for a specification of the language feature
design. Use `tasks/X/IMPL.md` for significant implementation
decisions. Mark design questions that need the user's review. Once
resolved, replace each question with the decision.

Link between these documents without repeating their contents.

## Working procedure

- Before an implementation task, read the relevant documents first.
- Follow existing Links conventions for routine choices. Ask the user
  before making unresolved choices that significantly affect which
  programs Links accepts, what annotations it requires, or how
  programs run.
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

## Build and test

Run all commands from the repository root.

### 1. Build

Use OCaml 5.3.0 or later. Install the build dependencies with
`opam install ./links.opam --deps-only`. Install `ounit2` for unit tests.

```sh
make
```

This builds the native interpreter and creates the `./links` launcher.
Use `make all-ci` for the CI build profile. Rebuild after changing
compiler code and before running tests. The test harness uses the
existing launcher and executable.

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

Run the OCaml IR unit tests when changing the code they cover:

```sh
opam exec -- ./run-tests unit-tests
```

`make tests` runs all top-level regression suites and the `.testscript`
checks. Run it before completing broad compiler changes.

### 3. Check source changes

```sh
make rule-check
git diff --check
```

For build and test results, report the command, tested source revision,
result, log path, and any relevant failure excerpts. For documentation
edits, also run any changed examples.

### 4. Check installation

For changes to installation or startup paths, build and install to a
temporary prefix, then check the installed interpreter from another
directory. See [INSTALL.md](INSTALL.md) for user installation commands.

```sh
make all-ci
prefix=$(mktemp -d "${TMPDIR:-/tmp}/smalllinks.XXXXXX")
opam exec -- dune install --profile=ci --prefix="$prefix" links
./tests/check-install.sh "$prefix/bin/linx"
```

## Code changes

- Make only changes needed for the requested outcome.
- Follow the surrounding OCaml and Links code style. Keep `.ml` and
  `.mli` files consistent. Follow the nearest `.ocamlformat` and
  avoid reformatting unrelated code.
- Use the official [OCaml Programming Guidelines](https://ocaml.org/docs/guidelines)
  for general coding style. Preserve local conventions where they differ.
- Edit lexer and parser sources (`.mll` and `.mly`), and let the build
  generate their OCaml files.
- Edit package metadata in `dune-project`. Include changes to
  `links.opam` regenerated by Dune.
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
