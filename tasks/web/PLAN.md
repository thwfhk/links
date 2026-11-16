# SmallLinks web demo plan

This plan records scope, milestones, progress and checks.
[IMPL.md](IMPL.md) describes the browser build, the interface between
the page and worker, and decisions to verify during implementation.
[GUIDE.md](../met/GUIDE.md) remains the source of the language guide.

Work stays on `small-web`, based on `small-met` at `59ef2511`.

## Scope

1. Build a static site that can check and run programs entered in the
   editor. **Check** shows the inferred type or a diagnostic.
   **Run** also shows the result and printed output. Each submission
   starts from the standard prelude. **Stop** ends the current request.
2. Let visitors load and edit existing repository examples. Include
   examples of functions, polymorphism and effect handlers. Run examples
   with imports when their dependencies are bundled with the site.
   Access to local files, raw TCP sockets and other host facilities is
   outside the initial scope.
3. Include a browsable copy of the language guide in the static build.
   Syntax highlighting is optional.

## Chat ownership

| Codex chat | Work | Chat ID |
| --- | --- | --- |
| SmallLinks web demo | Coordination, browser runtime, example and guide packaging, integration and final checks. | `01a1e515-5976-7681-af81-ca86443c6718` |
| SmallLinks playground page design | Milestone 2, including the editor, example selector, controls, results, guide navigation and optional CodeMirror highlighting. | `01a1e532-55bf-77d0-ac7e-b09c2f5119e0` |

The [worker interface](IMPL.md#worker-interface) is shared across both
chats. The webpage can use a mock worker while the runtime build is
in progress. Assign bounded work to subagents and one writer per file.

## Tracking

Commit each implementation item separately and keep each commit
buildable. Record the commit ID and mark the item complete after the
checks pass. At each pause, record the next action, blockers and latest
checks under [Status](#status).
For builds and tests, record the command, revision, result, and log path.

## Milestones

### 1. Build the browser runtime

- [x] **1.1** (`8dc038f3`) Share the parser, Fresco type checker and
  asynchronous evaluator with the browser build. Move terminal input
  into the native executable.
- [x] **1.2** (`7ed780ed`) Link the worker with `js_of_ocaml` and
  implement the worker messages. Load the standard prelude and route
  output and diagnostics to the page. Apply the browser primitive and
  import policies in [IMPL.md](IMPL.md#runtime).
- [x] **1.3** (`9313ad14`) Compare native and worker runs on supported
  cases. Run the single-yield example to exercise a handler resumption.
  Check a rejected program, printed output, early exit, an unavailable
  primitive, and imports of bundled and missing modules. Resolve or
  record browser-specific behaviour found by the checks.

Completion check — a worker can check and run an edited program and
report errors. The native interpreter still passes its affected checks.

### 2. Build the playground page

Can proceed alongside milestone 1 using the mock worker.

- [x] **2.1** (`a1fa3afc`) Build the editor, example selector, Check, Run and Stop
  controls, and output and diagnostics panel. Keep the editor usable
  with a keyboard and on narrow screens.
- [x] **2.2** (`c69df0d9`) Connect the page to the worker interface. Handle startup,
  running, stopping, and worker failure. Keep source edits when a
  request fails or is stopped.
- [x] **2.3** (`872be65a`) Add
  [CodeMirror highlighting](IMPL.md#editor-and-highlighting) for
  SmallLinks tokens.

Completion check — a visitor can edit, check, run and stop a program
with either the mock worker or the browser build.

### 3. Package repository examples and the guide

Can start while milestones 1 and 2 are in progress. Completion checks
use the real worker.

- [x] **3.1** (`16ab6afe`) Package selected repository examples and their imports at
  build time. Record the included paths and any candidates deferred
  because they need host facilities or fail in the browser. Verify the
  published entries against the repository sources.
- [x] **3.2** (`ddef3506`) Render the current language guide as static HTML. Connect
  the guide and editor, preserve heading links and Links code blocks,
  and check links to examples and other repository files.

Completion check — every advertised example loads and runs as
documented. The guide ships with the playground and its links work.

### 4. Integrate and verify the static build

Depends on milestones 1–3.

- [x] **4.1** (`ec52b280`) Add a repeatable build for the static output directory and
  document how to serve it over HTTP. Verify it at the site root and
  under a path prefix, with every required asset served from the build.
- [x] **4.2** (`25352686`) Test the page with typed code, an edited example, an
  imported example, a type error, a runtime error and a stopped run.
  Check that the next request starts cleanly after a timeout.
- [x] **4.3** Run the native checks below, record the combined results,
  and mark the plan complete when the required checks pass.

## Checks

1. Compare browser and CLI results for arithmetic, prelude and list
   helpers, polymorphism, handlers, module imports and diagnostics.
   Check a program that calls `print` and confirm that **Check** shows
   only its inferred type. Run it and verify that output emitted before
   an error is still visible. Include a long run that crosses an
   evaluator pause and consecutive requests that start from fresh state.
2. Load the static build in Node using a simulated DOM. Verify that
   the page resolves its assets at the site root and under a path
   prefix, that its controls have accessible names, and that it
   communicates with the compiled worker. Use Node checks for this
   milestone.
3. Rebuild native SmallLinks with `make` after changing shared code.
   Run the affected regression suites, including `handlers`,
   `effect_annotations`, `native`, `modules` and `typecheck_examples`
   when their paths change. Run the IR unit tests if the affected code
   is covered there and `make tests` for broad compiler changes.
   Follow the installation checks in [AGENTS.md](../../AGENTS.md) if
   native startup or installation paths change. Run `make rule-check`
   and `git diff --check` on the final changes.

## Status

The demo is complete on `small-web`. The
[static build](IMPL.md#build-and-serve) is in `web/dist`.
It includes the CodeMirror editor, five runnable examples and the
language guide. The [examples and guide notes](IMPL.md#examples-and-guide)
record the deferred handler test driver.

Final checks used the source in `25352686`. Logs are in
`/private/tmp/smalllinks-web.1oRIDH/final/`. The worker used OCaml
5.4.0 and `js_of_ocaml` 6.2.0. Web checks ran in Node and jsdom.

| Check | Result and log |
| --- | --- |
| `make test-web-demo test-web-runtime` | Both site suites and all 15 worker checks passed. The site suites cover the root and a path prefix, all five examples, the guide link, highlighting, diagnostics, Stop and timeout recovery. `web-tests.log`. |
| `make all-ci` and `make tests` | Passed. 1,335 tests passed across 43 suites, with two existing ignored cases. All six scripts passed. `native-build.log`, `native-tests.log`. |
| `opam exec -- ./run-tests unit-tests` | All 105 tests passed. `unit-tests.log`. |
| Temporary `dune install`, `./tests/check-install.sh` and the installed module-import example | All three installation checks passed. The installed example returned `(0, [0, 1, 2, 3, 4])`. `install.log`, `install-check.log`. |
| `make rule-check` and `git diff --check 59ef2511` | Passed. A direct scan covered tabs and local documentation links because GNU find was unavailable. `rule-check.log`, `source-check.log`. |
