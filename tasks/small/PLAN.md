# SmallLinks plan

SmallLinks is a native subset of Links for developing modal effect types.
First establish a smaller compiler with the current Links type and effect
inference. Adding modal effect types is a later task.

The [language guide](SPEC.md) describes the subset.
[Implementation notes](IMPL.md) record decisions and open questions.

## Scope

1. Keep functions and closures, recursion and mutual recursion, local and
   top-level bindings, pattern matching, tuples, lists and list
   comprehensions, records, variants, modules and imports. Keep file
   execution, `-e`, the REPL and type checking without evaluation.
2. Keep type inference, the value restriction, signatures, aliases,
   recursive types, and type, row and presence polymorphism. Keep
   FreezeML and value linearity; both are available in Links by default.
3. Keep effect rows, effect aliases, `wild`, and deep, shallow and
   parameterised handlers, including multi-shot resumptions. Enable
   handlers by default. Use the current default effect annotation rules.
   Keep `~>`, `x{:T}` and `x{-}`.
4. Remove database drivers, tables, queries, SQL, SPARQL, temporal
   database features, relational lenses, session types and exceptions,
   the opt-in control-flow linearity extension, JavaScript and the web
   stack. Also remove built-in processes and mailboxes, foreign code,
   formlets, pages and XML literals and utilities. Keep native `escape`,
   regular expressions and ordinary date/time utilities.
5. Delete files used only by removed features. Update shared code and keep
   examples and tests that still exercise the retained parts.

## Tracking

Refine the milestone lists during implementation as needed. Each
numbered item is one commit, including the related source, tests and
documentation. Split an item in the list first if it needs more than
one commit. Keep each commit buildable. Tick the item in its commit
once its checks pass. A milestone is complete when all its items and
its completion check pass.

Record the commit ID next to each completed item after committing it.

At each pause, record the current milestone, next item, any blockers
and the latest check results under [Status](#status). Record the
command, tested revision, result and log path, plus any useful failure
details. Update [IMPL.md](IMPL.md) with decisions and open questions as
work proceeds. Agree on changes to accepted programs, required
annotations or evaluation before implementing them.

## Milestones

### 1. Record the native baseline

- [x] **1.1** (`c6136506`) Build the Links revision before the cuts.
  Record compiler settings and check the native file, expression and
  REPL entry points.
- [x] **1.2** (`5f296788`) Record results for the retained language, handler,
  FreezeML, value linearity and IR tests. Identify mixed suites and
  examples before removing their dependencies.
- [x] **1.3** (`56a7b221`) Add missing tests for retained behaviour to the
  baseline suite. Cover both acceptance and rejection.

Completion check: the reference build and its passing cases can be
reproduced; existing failures are recorded separately.

### 2. Separate the native runtime

- [x] **2.1** (`4dd4748a`) Remove external database driver packages and
  their build and CI targets. Keep the shared database code until
  milestone 3.
- [x] **2.2** (`2639b06b`) Remove the web and JavaScript entry points
  and foreign code. Keep file execution, `-e`, the REPL and type checking.
- [x] **2.3** (`68c19606`) Remove formlets, pages and XML paths and their
  prelude and primitive definitions. Delete the browser backend and
  library when their callers are gone.
- [x] **2.4** (`aadfb528`) Remove session types, session exceptions and
  CP syntax. Preserve value linearity and ordinary handler dispatch.
  Update session-dependent tests whose purpose still applies.
- [x] **2.5** (`516a5544`) Remove native processes and mailboxes. Replace the
  evaluator's scheduler calls and delete the unused process and web
  runtime, request data and serialisation.

Completion check: the default prelude loads; files with imports,
expressions and REPL definitions run. Retained handler and continuation
tests pass, including deep recursion. Removed constructs are rejected.

### 3. Remove the remaining database and lens code

- [x] **3.1** (`eb457d6f`) Remove relational lens syntax, types,
  primitives and evaluation. Delete the lens library and its tests.
- [x] **3.2** (`447c8a5e`) Remove tables, queries, updates and temporal
  database features. Keep list generators, `where` and `orderby`.
- [x] **3.3** (`7aa69b42`) Remove SPARQL, the remaining database and
  query modules, and unused build dependencies and settings. Keep
  ordinary date/time.

Completion check: the build has no database, query or lens modules.
List, record and handler tests pass; removed database and lens
constructs are rejected.

### 4. Simplify effect and row syntax

- [x] **4.1** (`f888b2df`) Remove control-flow linearity, including its
  settings and source forms. Preserve linear functions, kinds and usage
  checks, FreezeML and ordinary multi-shot resumptions.
- [x] **4.2** (`9d1b400d`) Migrate retained examples and tests away from
  optional effect sugar. Use explicit shared tails, alias arguments
  and presence fields where needed.
- [x] **4.3** (`7aa53e07`) Fix annotation rules to the former default
  and remove the optional effect sugar policies. Keep operation type
  elaboration and anonymous row resolution. Replace tests of the
  removed policies with tests of the retained syntax, including `~>`,
  `x{:T}` and `x{-}`, and tests of rejected forms. Check that printed
  types can be parsed again.

Completion check: handler, polymorphism, FreezeML, row, value linearity,
type printing and typed IR tests pass. Recheck the retained examples
with their new signatures and verify the type printer's output can be
parsed again.

### 5. Verify the subset

- [x] **5.1** (`c5452cef`) Enable handlers by default and check handler
  programs in all three native entry points without `--enable-handlers`.
- [x] **5.2** (`8d08a03b`) Align the build, installation, CI, test runner
  and repository instructions with SmallLinks. Verify the installed
  executable finds its prelude and standard library.
- [x] **5.3** Expand the language guide to cover ordinary types and
  terms as well as effect handlers. Check the guide's examples, register
  the retained source examples and run all retained checks.

Completion check: a clean build and install succeed, all retained
regressions and native IR unit tests pass, and source checks pass.

## Checks

1. Run `make` after compiler edits and before running tests. Check `./links -e`,
   file execution with an import, a REPL definition followed by a call,
   and `./links --set=typecheck_only=true file.links`.
2. `./test-harness tests/<suite>.tests` runs the native interpreter
   through `./links`. It uses `-e` for inline tests and passes the
   filename for file tests. It checks output, errors and exit status.
   Run each affected suite separately, including `functions`,
   `freezeml`, `handlers`, `effectname`, `polymorphism`, `records`,
   `variants`, `presence_type_arg` and `typecheck_examples`. Keep
   suite settings for features still supported.
3. Cover multi-shot, shallow and parameterised handlers, forwarding,
   polymorphic operations and operations outside the permitted row.
   Keep accepted and rejected programs for rows, FreezeML and value
   linearity. Run the retained `typed_ir` and
   `recheck_frontend_transformations` cases after inference changes.
4. Run `opam exec -- ./run-tests unit-tests` when changing covered IR
   code. At the end, run all retained suites,
   the example registration check, `make rule-check` and `git diff --check`.

## Status

The SmallLinks plan is complete. A clean build and install pass, the
installed interpreter loads its runtime files, and all 35 source
examples type check. The language guide covers the retained syntax and
its examples pass. Modal effect types are a separate task. There are no
blockers or open design questions for this plan.

Checks for 5.3 used `8d08a03b` plus the item changes on OCaml 5.4.0
and Dune 3.20.2. Logs are under `/private/tmp/smalllinks-m5.sodOj9/`.
The macOS `xcrun` cache messages did not affect the check results.

| Command or check | Result | Log |
| --- | --- | --- |
| `make clean` and `make all-ci` | Clean CI-profile build passed. | `5.3-clean.log`, `5.3-build.log` |
| `opam exec -- dune install --profile=ci --prefix=… links` and `./tests/check-install.sh` for the staged binary | Passed from outside the checkout. | `5.3-install.log`, `5.3-installed.log` |
| `make tests` | 40 suites, 927 passed, 2 ignored and 0 failed. The two ignored cases are existing redundant-pattern tests. The example registration, REPL and five print and reparse checks passed. | `5.3-regressions.log` |
| `opam exec -- ./run-tests unit-tests` | All 44 IR unit tests passed. | `5.3-unit.log` |
| `./test-harness tests/typecheck_examples.tests` | All 35 examples type checked, including Church numerals. | `5.3-typecheck_examples.log` |
| Run each handler example with `./links --path=examples/handlers`. Run the installed handler runner and Church example with `linx`. | All 27 handler examples passed. The installed examples returned `()` and `4`. | `5.3-all-handler-examples.log`, `5.3-installed-examples.log` |
| Run the language guide's code with `./links` in file, expression, type-check-only and REPL modes | 33 checks passed, including every fenced Links block. | `5.3-guide.log` |
| `make rule-check`, `git diff --check` and check local links in the guide and setup files | Passed. The tabs check used `rg` because GNU find was unavailable. | `5.3-rule.log`, `5.3-diff.log`, `5.3-tabs.log`, `5.3-doc-links.log` |

Checks for 5.2 used `c5452cef` plus the item changes on OCaml 5.4.0
and Dune 3.20.2. Logs are under `/private/tmp/smalllinks-m5.sodOj9/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make`, `make all-ci` and `opam exec -- dune build --profile=ci @install` with a clean build directory | Passed. | `5.2-dev-build.log`, `5.2-ci-build.log`, `5.2-clean-build.log` |
| `opam exec -- dune build -p links @install` with a clean build directory | Passed with the new opam build rules. | `5.2-package-build.log` |
| `opam exec -- dune install --profile=ci --prefix=… links` and `./tests/check-install.sh` for the staged binary, repeated with `dev` | The installed executable used the prelude and imported the standard library from another directory. | `5.2-ci-install.log`, `5.2-ci-installed.log`, `5.2-dev-install.log`, `5.2-dev-installed.log` |
| Move a copy of the installed prefix, run the install check, then hide each runtime path in turn | The moved copy worked. Hiding its prelude or standard library caused the expected missing-file error. | `5.2-relocated.log`, `5.2-missing-prelude.log`, `5.2-missing-stdlib.log` |
| Compare installed and source example lists and run the installed handler example runner | All 35 source examples installed. The runner returned `()`. | `5.2-installed-examples.log`, `5.2-installed-handler-examples.log` |
| `make tests` and `opam exec -- ./run-tests unit-tests` | 925 regressions passed, 4 ignored and 0 failed. All 44 unit tests passed. | `5.2-regressions.log`, `5.2-unit.log` |
| `make rule-check`, `git diff --check` and parse the CI workflow YAML | Passed. The tabs check used `rg` because GNU find was unavailable. | `5.2-rule.log`, `5.2-diff.log`, `5.2-tabs.log`, `5.2-workflow.log` |

Checks for 5.1 used `7aa53e07` plus the item changes on OCaml 5.4.0.
Logs are under `/private/tmp/smalllinks-m5.sodOj9/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make no-db` | Passed. | `5.1-build.log` |
| `make tests` | 40 suites, 925 passed, 4 ignored and 0 failed. The REPL, print and reparse, and registration checks passed. | `5.1-regressions.log` |
| `./links -e`, `./links --path=examples/handlers examples/handlers/tests.links`, the same file with `--set=typecheck_only=true`, and `./tests/repl_handlers.testscript` | All four passed with handlers on by default. | `5.1-expr.log`, `5.1-file.log`, `5.1-typecheck.log`, `5.1-repl.log` |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed. | `5.1-unit.log` |
| `make rule-check` and `git diff --check` | Passed. The tabs check used `rg` because GNU find was unavailable. | `5.1-rule.log`, `5.1-diff.log`, `5.1-tabs.log` |

Milestone 4 is complete. The retained tests and examples pass with the
fixed effect annotation rules. The default printer's output is checked
by using it again as a type annotation.

Checks for 4.3 used `9d1b400d` plus the item changes on OCaml 5.4.0.
Logs are under `/private/tmp/smalllinks-m4.Fx8PK2/`. The macOS `xcrun`
cache messages did not affect the build or test results.

| Command or check | Result | Log |
| --- | --- | --- |
| `make no-db` and `make all-ci` | Passed. | `4.3-build.log`, `4.3-ci.log` |
| `make tests` | 40 suites, 923 passed, 4 ignored and 0 failed. All five print and reparse checks and the example registration check passed. | `4.3-regressions.log` |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed. | `4.3-unit.log` |
| `./links --enable-handlers --path=examples/handlers` with each handler example, with and without `--set=typecheck_only=true` | All 27 examples type checked and ran. | `4.3-all-handler-examples.log`, `4.3-example-*.log` |
| `./links --enable-handlers --path=examples/handlers examples/handlers/tests.links` and the same command with `--set=typecheck_only=true` | Imported examples ran and type checked. | `4.3-runner.log`, `4.3-typecheck.log` |
| `./links --enable-handlers -e` and `./links --enable-handlers` with REPL input | A multi-shot handler returned `[1, 2]`. The REPL bound and handled `ask`, returning `42`. | `4.3-expr.log`, `4.3-repl.log` |
| `make rule-check` and `git diff --check` | Passed. The tabs check used `rg` because GNU find was unavailable. | `4.3-rule.log`, `4.3-diff.log`, `4.3-tabs.log` |

Checks for 4.2 used the compiler at `f888b2df` with the item changes to
the examples and their tests. Logs are under `/private/tmp/smalllinks-m4.Fx8PK2/`
and `/private/tmp/smalllinks-4.2-fixtures.EjB2gU/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `./links --enable-handlers --path=examples/handlers examples/handlers/tests.links` | Passed, including the SAT assertions. | `4.2-runner.log` |
| `./test-harness tests/handlers.tests` and `./test-harness tests/typecheck_examples.tests` | 140 passed, 1 ignored and 0 failed. | `4.2-handlers.log`, `4.2-typecheck_examples.log` |
| `./links --enable-handlers --path=examples/handlers` with each handler example, with and without `--set=typecheck_only=true` | All 27 examples type checked and ran. | `shared-runtime-all-handlers.log`, `shared-typecheck-all-handlers.log` |
| REPL `@typeenv` comparison before and after migration | Printed types match for all seven migrated examples with quantifiers shown. | `shared-typeenv-*.diff.log` |
| `./tests/validate_typecheck_testfile.testscript`, `make rule-check` and `git diff --check` | Passed. The tabs check used `rg` because GNU find was unavailable. | `4.2-registration.log`, `4.2-rule.log`, `4.2-diff.log`, `4.2-tabs.log` |

Checks for 4.1 used `7aa69b42` plus the item changes on OCaml 5.4.0.
Logs are under `/private/tmp/smalllinks-m4.Fx8PK2/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make no-db` | Passed. | `4.1-build.log` |
| `./test-harness tests/<suite>.tests` for the suites below | 566 passed, 2 ignored and 0 failed. | One `4.1-<suite>.log` per suite |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed. | `4.1-unit.log` |
| `./tests/validate_typecheck_testfile.testscript` | Passed. | `4.1-registration.log` |
| `make rule-check` and `git diff --check` | Passed. The tabs check used `rg` because GNU find was unavailable. | `4.1-rule.log`, `4.1-diff.log`, `4.1-tabs.log` |

Suites for 4.1: `desugar_datatypes`, `effect_sugar`, `effectname`,
`freezeml`, `functions`, `handlers`, `native`, `polymorphism`,
`presence_type_arg`, `recheck_frontend_transformations`, `records`,
`roundtrippable_types`, `type_print`, `typecheck_examples`, `typed_ir`
and `variants`.

Milestone 3 is complete. A clean build contains no database, query or
lens modules. List, record, handler and ordinary date/time tests pass,
and the removed constructs are rejected.

Checks for 3.3 used `447c8a5e` plus the item changes on OCaml 5.4.0.
Logs are under `/private/tmp/smalllinks-m3.yjxu5W/`. The macOS `xcrun`
cache messages in the logs did not affect the check results.

| Command or check | Result | Log |
| --- | --- | --- |
| `make no-db` and `make all-ci` | Passed. | `3.3-build.log`, `3.3-ci.log` |
| `opam exec -- dune build --build-dir=/private/tmp/smalllinks-m3.yjxu5W/clean-build @install` | Clean build passed. | `3.3-clean-build.log` |
| `opam exec -- ocamlobjinfo` on the clean build's `links_core.cmxa` | No database, query or lens modules. | `3.3-compiled-modules.log` |
| `opam exec -- dune describe external-lib-deps` and `opam exec -- dune build links.opam` | The removed libraries are absent from the dependency list and generated metadata. | `3.3-dependencies.log`, `3.3-opam.log` |
| `make tests` | 43 suites, 1,110 passed, 6 ignored and 0 failed. | `3.3-regressions.log` |
| `./test-harness tests/native.tests` and `./test-harness tests/datetime.tests` | 62 and 27 passed. | `3.3-native.log`, `3.3-datetime.log` |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed without a database test config. | `3.3-unit.log` |
| Native expression, file with imports, typecheck-only file and REPL checks | Passed. | `3.3-expr.log`, `3.3-file.log`, `3.3-typecheck.log`, `3.3-repl.log` |
| List generator with subtraction, `where` and `orderby` | Printed `[2, 3] : [Int]`. | `3.3-grammar.log` |
| `./tests/validate_typecheck_testfile.testscript` | Passed. | `3.3-registration.log` |
| `make rule-check` and `git diff --check` | Passed. GNU find was unavailable, so the tabs check was repeated with `rg` and found no tabs. | `3.3-rule.log`, `3.3-diff.log`, `3.3-tabs.log` |

Checks for 3.2 used `eb457d6f` plus the item changes on OCaml 5.4.0.
Logs are under `/private/tmp/smalllinks-m3.yjxu5W/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make no-db` and `make all-ci` | Passed. | `3.2-build.log`, `3.2-ci.log` |
| Native expression, file with imports, typecheck-only file and REPL checks | Passed. | `3.2-expr.log`, `3.2-file.log`, `3.2-typecheck.log`, `3.2-repl.log` |
| `./test-harness tests/<suite>.tests` for the suites below | 619 passed, 3 ignored and 0 failed. | One `3.2-<suite>.log` per suite |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed. | `3.2-unit.log` |
| `./links examples/factorial.links` and `./links examples/paginate.links` | Passed with list data. | `3.2-factorial.log`, `3.2-paginate.log` |
| `./tests/validate_typecheck_testfile.testscript` | Passed. | `3.2-registration.log` |
| `make rule-check` and `git diff --check` | Passed. GNU find was unavailable for the tabs rule. | `3.2-rule.log`, `3.2-diff.log` |

Suites for 3.2: `collections`, `datetime`, `effect_sugar`, `effectname`,
`freezeml`, `functions`, `handlers`, `lexing`, `native`, `parser`,
`polymorphism`, `presence_type_arg`, `recheck_frontend_transformations`,
`records`, `roundtrippable_types`, `typecheck_examples`,
`typecheck_examples_with_cfl_on`, `typed_ir` and `variants`.

Checks for 3.1 used `516a5544` plus the item changes on OCaml 5.4.0.
Logs are under `/private/tmp/smalllinks-m3.yjxu5W/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make no-db` and `make all-ci` | Passed. | `3.1-build.log`, `3.1-ci.log` |
| Native expression, file with imports, typecheck-only file and REPL checks | Passed. | `3.1-expr.log`, `3.1-file.log`, `3.1-typecheck.log`, `3.1-repl.log` |
| `./test-harness tests/<suite>.tests` for the suites below | 546 passed, 8 ignored and 0 failed. The native suite includes seven lens removal cases. | One `3.1-<suite>.log` per suite |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed. | `3.1-unit.log` |
| `./tests/validate_typecheck_testfile.testscript` | Passed. | `3.1-registration.log` |
| `make rule-check` and `git diff --check` | Passed. GNU find was unavailable for the tabs rule. | `3.1-rule.log`, `3.1-diff.log` |

Suites for 3.1: `collections`, `database`, `effect_sugar`, `freezeml`,
`handlers`, `native`, `parser`, `polymorphism`,
`recheck_frontend_transformations`, `records`, `roundtrippable_types`,
`temporal`, `typecheck_examples`, `typecheck_examples_with_cfl_on` and
`typed_ir`.

### Milestone 2

Milestone 2 is complete. The prelude, native entry points, handlers,
continuations and rejection checks passed.

Checks for 2.5 used `aadfb528` plus the item changes on OCaml 5.4.0.
Logs are under `/private/tmp/smalllinks-m2.B3p5xp/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make no-db` and `make all-ci` | Passed. | `2.5-build.log`, `2.5-ci.log` |
| `opam exec -- dune build --build-dir=/private/tmp/smalllinks-m2.B3p5xp/clean-build @install` | Clean build passed. | `2.5-clean-build.log` |
| `make tests` | 46 suites, 1,148 passed, 11 existing ignores and 0 failures. | `2.5-regressions.log` |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed. | `2.5-unit.log` |
| Native expression, handler file with imports, typecheck-only file and REPL checks | All passed. | `2.5-expr.log`, `2.5-file.log`, `2.5-typecheck.log`, `2.5-repl.log` |
| `./links --set=typecheck_only=true -e 'error("evaluated")'` | Exited successfully without evaluating the expression. | `2.5-typecheck-expr.log` |
| `./links -e 'fun down(n) { if (n == 0) 42 else down(n - 1) } down(100000)'` | Printed `42 : Int`. | `2.5-depth.log` |
| Arithmetic and list length in two resumptions of a handler | Printed `45 : Int`. | `2.5-pure.log` |
| `./links examples/TicTacToe-Console.links` | Ran successfully. | `2.5-tic-tac-toe.log` |
| `./tests/validate_typecheck_testfile.testscript` | Passed. | `2.5-registration.log` |
| `make rule-check` and `git diff --check` | Passed. GNU find was unavailable, so the tabs check was repeated with `rg`. It found no tabs in the checked files. | `2.5-rule.log`, `2.5-diff.log`, `2.5-tabs-fallback.log` |

After committing 2.5, `./test-harness tests/native.tests` passed all 39
cases on `516a5544`. See `2.5-committed-native.log`.

Checks for 2.4 used `68c19606` plus the item changes on OCaml 5.4.0.
Logs are under `/private/tmp/smalllinks-m2.B3p5xp/`.

| Command | Result | Log |
| --- | --- | --- |
| `make no-db` and `make all-ci` | Passed. | `2.4-build.log`, `2.4-ci.log` |
| Native expression, file with imports, typecheck-only file and REPL checks | All passed. | `2.4-expr.log`, `2.4-file.log`, `2.4-typecheck.log`, `2.4-repl.log` |
| `./test-harness tests/<suite>.tests` for the suites below | 811 passed and 8 were ignored. | One `2.4-<suite>.log` per suite |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed. | `2.4-unit.log` |
| `./tests/validate_typecheck_testfile.testscript` | Passed. | `2.4-registration.log` |
| `make rule-check` and `git diff --check` | Passed. GNU find was unavailable for the tabs rule. | `2.4-rule.log`, `2.4-diff.log` |

Suites for 2.4: `annotations`, `cliArgs`, `collections`, `continuations`,
`control_flow_linearity`, `database`, `desugar_datatypes`, `effect_sugar`,
`effectname`, `freezeml`, `functions`, `handlers`, `lexing`, `messages`,
`modules`, `mutual`, `native`, `parser`, `polymorphism`,
`presence_type_arg`, `recheck_frontend_transformations`, `records`,
`regex`, `relational_lenses`, `roundtrippable_types`, `type_print`,
`typecheck_examples`, `typecheck_examples_with_cfl_on`, `typed_ir`,
`variants`.

Checks for 2.3 used `2639b06b` plus the item changes on OCaml 5.4.0.
Logs are under `/private/tmp/smalllinks-m2.B3p5xp/`.

| Command | Result | Log |
| --- | --- | --- |
| `make no-db` and `make all-ci` | Passed. | `2.3-build.log`, `2.3-ci.log` |
| Native expression, file with imports, typecheck-only file and REPL checks | All passed. | `2.3-expr.log`, `2.3-file.log`, `2.3-typecheck.log`, `2.3-repl.log` |
| `./test-harness tests/<suite>.tests` for the suites below | 715 passed and 12 were ignored. | One `2.3-<suite>.log` per suite |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed. | `2.3-unit.log` |
| `./tests/validate_typecheck_testfile.testscript` | Passed. | `2.3-registration.log` |
| `make rule-check` and `git diff --check` | Passed. GNU find was unavailable for the tabs rule. | `2.3-rule.log`, `2.3-diff.log` |

Suites for 2.3: `booleans`, `builtins`, `cliArgs`, `collections`,
`continuations`, `crypt`, `datetime`, `effect_sugar`, `freezeml`,
`functions`, `handlers`, `lexing`, `modules`, `native`, `parser`,
`polymorphism`, `presence_type_arg`, `records`,
`recheck_frontend_transformations`, `regex`, `roundtrippable_types`,
`session-exceptions`, `sessions`, `type_print`, `typecheck_examples`,
`typecheck_examples_with_cfl_on`, `typed_ir`.

Checks for 2.2 used `4dd4748a` plus the item changes on OCaml 5.4.0.
Logs are under `/private/tmp/smalllinks-m2.B3p5xp/`.

| Command | Result | Log |
| --- | --- | --- |
| `make no-db` | Passed. | `2.2-build.log` |
| Native expression, file with imports, typecheck-only file, REPL and extensible case example checks | All passed. | `2.2-expr.log`, `2.2-file.log`, `2.2-typecheck.log`, `2.2-repl.log`, `2.2-extensible-case.log` |
| `./test-harness tests/<suite>.tests` for the suites below | 541 passed and 13 were ignored. | One `2.2-<suite>.log` per suite |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed. | `2.2-unit.log` |
| `./tests/validate_typecheck_testfile.testscript` | Passed. | `2.2-registration.log` |
| `make rule-check` and `git diff --check` | Passed. GNU find was unavailable for the tabs rule. | `2.2-rule.log`, `2.2-diff.log` |

Suites for 2.2: `booleans`, `cliArgs`, `continuations`, `effect_sugar`,
`functions`, `handlers`, `modules`, `native`, `page`, `polymorphism`,
`records`, `recheck_frontend_transformations`, `session-exceptions`,
`sessions`, `typecheck_examples`, `typecheck_examples_with_cfl_on`,
`typed_ir`.

Checks for 2.1 used `f0a027bc` plus the item changes on OCaml 5.4.0.
Logs are under `/private/tmp/smalllinks-m2.B3p5xp/`.

| Command | Result | Log |
| --- | --- | --- |
| `make no-db` and `make all-ci` | Passed. | `2.1-build.log`, `2.1-ci.log` |
| `opam exec -- dune build links.opam` and check driver files | Main metadata unchanged. No external driver files. | `2.1-driver-packages.log` |
| Native expression, file with imports, typecheck-only file and REPL checks | All passed. | `2.1-expression.log`, `2.1-import.log`, `2.1-typecheck.log`, `2.1-repl.log` |
| `./test-harness tests/functions.tests` and `./test-harness tests/handlers.tests` | 34 and 100 passed. | `2.1-functions.log`, `2.1-handlers.log` |
| `opam exec -- ./run-tests nodb-unit-tests` | 44 passed. | `2.1-unit.log` |
| `./tests/validate_typecheck_testfile.testscript` | Passed. | `2.1-example-registration.log` |
| `make rule-check` and `git diff --check` | Passed. GNU find was unavailable for the tabs rule. | `2.1-rules.log`, `2.1-diff.log` |

### Milestone 1 baseline

Milestone 1 is complete. The build and native entry checks passed on
`1912d9b7` with OCaml 5.4.0. Baseline settings were the Links defaults
unless the commands or suites specify otherwise. Handlers, optional
effect sugar and control-flow linearity were off by default.

Across the 39 baseline suites, 986 cases passed and 18 were ignored
after adding the ten cases in 1.3. All 44 native IR unit tests passed.

| Command on `1912d9b7` | Result | Log under `/private/tmp/smalllinks-m1.yNp7d5/` |
| --- | --- | --- |
| `make no-db` | Passed with `xcrun` cache warnings. | `build.log` |
| `./links -e '40 + 2'` | Printed `42 : Int`. | `expression.log` |
| `./links --enable-handlers --path=examples/handlers --set=effect_sugar=true --set=effect_sugar_policy=final_arrow examples/handlers/tests.links` | Evaluated the handler examples with imports and printed `() : ()`. | `file.log` |
| `./links --enable-handlers --set=typecheck_only=true examples/handlers/identity.links` | Exited successfully with no output. | `typecheck.log` |
| `./links` with `fun inc(x) { x + 1 };`, `inc(41);` and `@quit;` | Printed the function type and `42 : Int`. | `repl.log` |
| `./test-harness tests/<suite>.tests` for each additional suite below | 307 passed and 3 were ignored. | One log per suite |
| `opam exec -- ./run-tests nodb-unit-tests` with `tests/unit/config.nodb.sample` | 44 passed. | `ir-unit.log` |
| `./tests/validate_typecheck_testfile.testscript` | Passed. | `example-registration.log` |
| `make rule-check` | Passed. The tabs rule skipped its check because GNU find was unavailable. | `rule-check.log` |

| Command or check | Result on `4e5c78c5` | Log |
| --- | --- | --- |
| `./test-harness tests/<suite>.tests` for each suite below | 669 passed, 15 ignored by the existing example suite, 0 failed. | `/private/tmp/smalllinks-review-tests.Ux21Wd/` (one log per suite) |
| Run the source examples from `SPEC.md` with `./links -e` | All six examples passed; the duplicate call of the linear function was rejected. | `/private/tmp/smalllinks-spec-final.qXtMJF` |

Suites run during planning: `annotations`, `collections`, `continuations`,
`desugar_datatypes`, `effect_sugar`, `effectname`, `freezeml`,
`functions`, `handlers`, `polymorphism`, `presence_type_arg`,
`recheck_frontend_transformations`, `records`, `roundtrippable_types`,
`type_print`, `typecheck_examples`, `typed_ir`, `variants`.

Additional suites: `binaryTrees`, `bindings`, `booleans`, `builtins`,
`char_operations`, `cliArgs`, `conditionals`, `crypt`, `datetime`,
`lexing`, `library`, `modules`, `mutual`, `numbers`, `operators`,
`parser`, `patterns`, `regex`, `strings`, `switch_functions`, `tuples`.

The existing ignored cases are 15 example type checks, two redundant
pattern checks and the `Quasituples` printer check. The logs list
their names and reasons. The handler example runner passes with its
own settings in `handlers.tests` despite its ignored entry in the
example typecheck suite.

Tests added in 1.3 cover deep recursion, braced record and operation
fields, explicit FreezeML application of row and presence arguments,
and the use of linear values in deep and shallow handlers and repeated
resumptions. The checks used `5f296788` with the test additions and the
baseline compiler. Logs are under `/private/tmp/smalllinks-m1.yNp7d5/`.

| Command | Result | Log |
| --- | --- | --- |
| `./test-harness tests/functions.tests` | 34 passed. | `functions-with-baseline-cases.log` |
| `./test-harness tests/freezeml.tests` | 61 passed. | `freezeml-with-baseline-cases.log` |
| `./test-harness tests/handlers.tests` | 100 passed. | `handlers-with-baseline-cases.log` |
| `./test-harness tests/records.tests` | 32 passed. | `records-with-baseline-cases.log` |
| `make rule-check` | Passed with the same tabs skip. | `rule-check-with-baseline-cases.log` |
| `git diff --check` | Passed. | No output |
