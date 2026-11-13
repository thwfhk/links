# SmallLinks plan

SmallLinks is a native subset of Links for developing modal effect types.
First establish a smaller compiler with the current Links type and effect
inference. Adding modal effect types is a later task.

The [language draft](SPEC.md) describes the subset.
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

At each pause, record the current milestone, next item, any blockers
and the latest check results under [Status](#status). Record the
command, tested revision, result and log path, plus any useful failure
details. Update [IMPL.md](IMPL.md) with decisions and open questions as
work proceeds. Agree on changes to accepted programs, required
annotations or evaluation before implementing them.

## Milestones

### 1. Record the native baseline

- [x] **1.1** Build the Links revision before the cuts. Record compiler
  settings and check the native file, expression and REPL entry points.
- [x] **1.2** Record results for the retained language, handler, FreezeML,
  value linearity and IR tests. Identify mixed suites and examples
  before removing their dependencies.
- [x] **1.3** Add any missing tests for retained behaviour to the baseline
  suite. Cover both acceptance and rejection.

Completion check: the reference build and its passing cases can be
reproduced; existing failures are recorded separately.

### 2. Separate the native runtime

- [ ] **2.1** Remove external database driver packages and their build
  and CI targets. Keep the shared database code until milestone 3.
- [ ] **2.2** Remove the web and JavaScript entry points and foreign code.
  Keep file execution, `-e`, the REPL and type checking.
- [ ] **2.3** Remove formlets, pages and XML paths and their prelude and
  primitive definitions. Delete the browser backend and library when
  their callers are gone.
- [ ] **2.4** Remove session types, session exceptions and CP syntax.
  Preserve value linearity and ordinary handler dispatch. Update
  session-dependent tests whose purpose still applies.
- [ ] **2.5** Remove native processes and mailboxes. Replace the
  evaluator's scheduler calls and delete the unused process and web
  runtime, request data and serialisation.

Completion check: the default prelude loads; files with imports,
expressions and REPL definitions run. Retained handler and continuation
tests pass, including deep recursion. Removed constructs are rejected.

### 3. Remove the remaining database and lens code

- [ ] **3.1** Remove relational lens syntax, types, primitives and
  evaluation. Delete the lens library and tests specific to it.
- [ ] **3.2** Remove tables, queries, updates and temporal database
  features. Keep list generators, `where` and `orderby`.
- [ ] **3.3** Remove SPARQL, the remaining database and query modules,
  and unused build dependencies and settings. Keep ordinary date/time.

Completion check: the build has no database, query or lens modules.
List, record and handler tests pass; removed database and lens
constructs are rejected.

### 4. Simplify effect and row syntax

- [ ] **4.1** Remove control-flow linearity, including its settings and
  source forms. Preserve linear functions, kinds and usage checks,
  FreezeML and ordinary multi-shot resumptions.
- [ ] **4.2** Migrate retained examples and tests away from optional
  effect sugar. Use explicit shared tails, alias arguments and
  presence fields where needed.
- [ ] **4.3** Fix annotation rules to the current default and remove the
  optional effect sugar policies. Keep operation type elaboration and
  anonymous row resolution. Replace tests of the removed policies with
  tests of the retained syntax, including `~>`, `x{:T}` and `x{-}`, and
  tests of rejected forms. Check that printed types can be parsed again.

Completion check: handler, polymorphism, FreezeML, row, value linearity,
type printing and typed IR tests pass. Recheck the retained examples
with their new signatures and verify the type printer's output can be
parsed again.

### 5. Verify the subset

- [ ] **5.1** Enable handlers by default and check handler programs in
  all three native entry points without `--enable-handlers`.
- [ ] **5.2** Align the build, installation, CI and test runner with
  SmallLinks. Verify the installed executable finds its prelude and
  standard library.
- [ ] **5.3** Finish the language draft, register the retained examples
  and run all retained checks.

Completion check: a clean build and install succeed, all retained
regressions and native IR unit tests pass, and source checks pass.

## Checks

1. Use `make no-db` for the baseline and as long as the target exists.
   Rebuild before running tests after compiler edits. Check `./links -e`,
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
4. Run `opam exec -- ./run-tests nodb-unit-tests` when changing covered IR
   code, or its native replacement. At the end, run all retained suites,
   the example registration check, `make rule-check` and `git diff --check`.

## Status

Milestone 1 is complete. The build and native entry checks passed on
`1912d9b7` with OCaml 5.4.0. Baseline settings were the Links defaults
unless the commands or suites specify otherwise. Handlers, optional
effect sugar and control-flow linearity were off by default.

Across the 39 baseline suites, 986 cases passed and 18 were ignored
after adding the ten cases in 1.3. All 44 native IR unit tests passed.
Next, start 2.1 by removing the external database driver packages and
their dedicated Make and CI targets. Keep the database code still used
by the compiler until milestone 3. There are no blockers for 2.1.

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
