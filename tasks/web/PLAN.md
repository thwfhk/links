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
   examples of functions, polymorphism and effect handlers. Group the
   runnable choices by topic in the playground. Run examples with
   imports when their dependencies are bundled with the site.
   Access to local files, raw TCP sockets and other host facilities is
   outside the initial scope.
3. Provide a source viewer for repository examples and the demo's
   bundled modules. Let visitors inspect the files an example imports
   and open runnable examples in the playground.
4. Include concise language documentation based on the existing guide.
   Link complete examples from the documentation to the playground.
5. Add a `wasm_of_ocaml` runtime alongside the existing `js_of_ocaml`
   runtime. Let visitors choose either runtime in the shared playground.
   Both use the same guide, example catalogue and worker messages.

## Chat ownership

| Codex chat | Work | Chat ID |
| --- | --- | --- |
| SmallLinks web demo | Coordination, example catalogue and worker packaging, static build integration and final checks. | `01a1e515-5976-7681-af81-ca86443c6718` |
| SmallLinks playground page design | Editor and controls, runtime selector, source viewer, and the structure and presentation of the web language documentation. | `01a1e532-55bf-77d0-ac7e-b09c2f5119e0` |

The [worker interface](IMPL.md#worker-interface) is shared across both
chats. The webpage can use a mock worker while the runtime build is
in progress. Assign bounded work to subagents and one writer per file.

## Tracking

Track each implementation item and follow-up in this plan and commit
each separately. Keep each commit buildable. Record the commit ID and
mark the item complete after the checks pass. Put follow-up changes to
the playground or guide interface under
[Web design updates](#web-design-updates).
At each pause, record the next action, blockers and latest checks under
[Status](#status).
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
- [x] **4.3** (`82cf4685`) Run the native checks below, record the
  combined results and mark the plan complete when the checks pass.

### 5. Expand the example catalogue and add a source viewer

- [x] **5.1** (`be970847`) Index the tracked `.links` files under
  `examples/` and the prelude and library sources used by the demo.
  Expand the runnable selection with existing examples of functions,
  lists, linear types and handlers. Start with `church.links`, `linearList.links`,
  `list-map-fold.links` and `handler_results.links`. Verify each
  advertised runnable example with the worker under the playground's
  timeout. Include its import dependencies.
- [x] **5.2** (`476fe5a9`) Add a read-only source viewer grouped by
  repository directory. Show the file path and let visitors follow
  imports.
  Provide a link that loads a runnable file in the playground for
  editing, checking and running. Show which files require a caller,
  rely on unavailable host features, exceed the timeout or illustrate
  an expected type error. Link support modules to a runnable caller
  where one exists.
- [x] **5.3** (`49d892af`) Replace the example dropdown with a
  catalogue organised by topic. Let visitors load an example or
  inspect its source from the catalogue. From
  [the shallow-handler example](../../examples/handlers/module_import.links),
  follow `Shallow_state` to
  [`shallow_state.links`](../../examples/handlers/shallow_state.links).
  The current build already copies that file. Confirm that opening it
  in the viewer preserves the editor contents and that the calling
  example still runs with its import.

Completion check — visitors can browse the example and module sources,
follow imports and load an expanded selection of verified programs.

### 6. Reorganise the web language documentation

The chapter outline can proceed alongside milestone 5. Runnable links
use the catalogue from 5.1.

- [x] **6.1** (`161a62fc`) Write a concise set of web chapters based on
  [the existing guide](../met/GUIDE.md). Start with basics, data and
  patterns, then cover functions and types, modules and imports,
  effects and handlers, and modal types and linearity. Give each
  chapter a short explanation of the syntax and a few examples with
  their results. Use the
  [OCaml Manual's core-language chapter](https://ocaml.org/manual/5.5/coreexamples.html)
  as a model for topic navigation and worked examples. Link to the
  full SmallLinks guide for detailed rules.
- [x] **6.2** (`27f15ea3`) Add chapter navigation and links to load complete
  examples in the playground. Reuse repository examples where
  they illustrate the topic. Preserve the source name and import
  context for multi-file examples. Give short syntax fragments the
  context needed to understand them.
- [x] **6.3** (`343a1723`) Verify the generated documentation, source
  viewer and runnable links together. Use Node and a simulated DOM at
  the site root and under a path prefix. Check that each runnable link loads
  the code shown or referenced by the chapter and runs with the
  expected result. Check chapter anchors and links to source files.

Completion check — visitors can find a language topic, read a
short explanation and open its complete examples in the playground.

## Web design updates

### 7. Combine source browsing and editing

- [x] **7.1** Put the complete directory list and common example
  shortcuts on the left of the playground. Show a file in read-only
  mode in the source pane and let visitors load it for editing and
  running. Keep the current draft available while browsing files or
  following imports and callers within the playground.
- [x] **7.2** Use the same header, compact typography and sidebar
  layout on the guide and playground. Put the guide's chapter list
  on the left. Route source links to the playground.
- [x] **7.3** Verify preview, loading, draft recovery, imports,
  guide links and worker requests in Node at the root and under a
  path prefix.

Completion check — visitors can browse and run sources in the
playground and navigate the guide from its chapter sidebar.

### 8. Expand the guide and revise the example shortcuts

- [x] **8.1** (`23b521dd`) Expand the chapters from the full SmallLinks
  guide. Give modal effect types their own chapter with worked examples.
  Align the guide's content column and code listings with the playground
  layout.
- [x] **8.2** (`7e6fb46e`) Make the example shortcuts a compact list
  and include examples of modal effect types. Remove the generic import
  note while keeping links to callers.

Completion check — readers can open and run the guide's listings and
find modal effect examples directly in the playground sidebar.

## Runtime updates

### 9. Add a WebAssembly build with wasm_of_ocaml

Depends on the runtime, static packaging and checks from milestones
1–6. The user authorised implementation on 17 November 2026.

Keep the existing JavaScript runtime and its build target. Add a
WebAssembly runtime target. Package both in `web/dist` and publish one
playground with a **Runtime** selector offering **JavaScript** and
**WebAssembly**. JavaScript is initially selected. The Pages artifact
includes both workers, the WebAssembly assets and the shared guide
and catalogue.

Continue coordination in this chat with bounded subagent tasks for
the runtime, build and verification. The existing playground-design
chat owns the runtime selector and its page interaction checks in 9.3.
The coordinator integrates the changes and records the final checks.

- [x] **9.1** (`bab0edd8`) Establish the toolchain and compatibility
  requirements.
  Select compatible OCaml, `wasm_of_ocaml-compiler`, `js_of_ocaml`
  libraries, Binaryen, Dune and Node versions. Reuse `js_of_ocaml`
  browser bindings and `js_of_ocaml-lwt` scheduling with the Wasm
  compiler. Audit dependencies, native primitives, JavaScript
  conversions and browser
  detection in `core/linkspath.ml`. Choose a build rule compatible with
  the project's Dune configuration and an explicit OCaml effect
  compilation mode compatible with the selected Node version. Record
  the engine requirements and decisions in [IMPL.md](IMPL.md).
- [x] **9.2** (`add29f2e`, `a1820b4a`) Build the WebAssembly worker from
  the shared OCaml runtime. Reuse the existing worker messages,
  prelude, embedded standard library and example imports. Handle asynchronous module
  loading before sending `ready`. Keep browser primitive restrictions,
  output limits and a fresh worker for each request. Resolve required
  primitive bindings and path handling, and check startup, one program
  and an imported example in Node.
- [x] **9.3** (`774da697`) Add the runtime selector to the shared
  playground. Use the selected worker for the next Check or Run.
  Disable the selector while a request is active. Preserve the editor text, source
  and import context, and displayed output when the selection changes.
  Keep the selection through example and guide navigation. Report an
  unsupported WebAssembly engine or a loader failure in the existing
  startup diagnostics so the visitor can select JavaScript.
- [x] **9.4** (`61a7a4b0`, `17fe5476`) Package the shared demo with both
  runtimes. Add repeatable runtime and site build targets. Copy the
  generated JavaScript loader and its complete asset directory,
  including the Wasm modules. Resolve
  assets relative to the shared site at the root and under a hosting
  prefix. Document installation, building and serving the shared output
  in [IMPL.md](IMPL.md).
- [x] **9.5** (`66d12b1e`, `1a93d5dd`) Check both runtimes. Reuse the
  Node worker loader where compatible and extend the site tests to
  exercise the WebAssembly assets. Run both runtimes through the worker
  and Node/jsdom suites,
  covering every runnable example and guide listing. Compare types,
  values, output, diagnostics, imports, Unicode, handler resumptions
  and early exits. Check the selector, retained editor state and
  navigation with each runtime.
  Check Stop, timeout recovery and failed or missing runtime assets.
  Test integer boundaries and overflow for each target. Run native
  checks for any shared code changes and record revisions and logs.
- [x] **9.6** (`2d4c143d`) Extend Pages packaging to include both
  runtimes. Build and check both runtime outputs in the deployment
  workflow, assemble one static artifact with the selector and both
  workers, and verify every
  loader and asset path over HTTP using Node. Document runtime selection and
  the required Pages environment branch rule. Record each implementation
  commit and mark the milestone complete after its checks pass.

SmallLinks `Int` uses each target's ordinary OCaml integer behaviour.
Document the target's range and test arithmetic at its boundaries.
The Wasm compiler uses signed 31-bit integers, with range
−1,073,741,824 to 1,073,741,823. The JavaScript compiler uses signed
32-bit integers, with range −2,147,483,648 to 2,147,483,647. For
example, `1073741823 + 1` wraps to `-1073741824` in Wasm and produces
`1073741824` in JavaScript.
[Upstream integer configuration](https://github.com/ocsigen/js_of_ocaml/blob/6.2.0/compiler/lib/config.ml)
and [OCaml WebAssembly target](https://ocaml.org/tools/wasm-target).

The compiler produces a JavaScript loader and an asset directory and
supports embedded files with `--file`. Use its JavaScript bindings and
Lwt support for the browser worker. Select the OCaml effect compilation
mode after checking the runtime and its dependencies.
[Wasm_of_ocaml manual](https://ocsigen.org/js_of_ocaml/latest/js_of_ocaml/wasm_overview.html)
and [Dune Wasm builds](https://dune.readthedocs.io/en/stable/wasmoo.html).

Completion check — both runtime targets build independently and coexist
in the Pages artifact. A visitor can select either runtime in the
shared playground and check and run the same editor contents. Both
workers pass the runtime and site checks, and target-specific behaviour
is documented. Automated checks use Node and jsdom. The user performs
the final browser check.

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
   communicates with the compiled worker. Exercise the source viewer,
   imported files and documentation links in the same checks.
3. Rebuild native SmallLinks with `make` after changing shared code.
   Run the affected regression suites, including `handlers`,
   `effect_annotations`, `native`, `modules` and `typecheck_examples`
   when their paths change. Run the IR unit tests if the affected code
   is covered there and `make tests` for broad compiler changes.
   Follow the installation checks in [AGENTS.md](../../AGENTS.md) if
   native startup or installation paths change. Run `make rule-check`
   and `git diff --check` on the final changes.

## Status

Milestone 9 implementation and automated checks are complete on
`small-web`. The shared static site in `web/dist` contains both
runtimes, 20 runnable examples, 101 browsable source files and 22
runnable guide listings. The next action is the user's final browser
check. Runtime and build work used subagents in this chat, and the
existing playground-design chat implemented the selector and site
checks.

### WebAssembly verification

The final combined web checks used source revision `17fe5476`, OCaml
5.4.0, Dune 3.20.2, matching compiler libraries 6.5.0, Binaryen 123 and
Node.js 22.23.5. The same worker and site checks also passed on Node.js
26.0.0. The [toolchain notes](IMPL.md#webassembly-toolchain) record the
dependencies and browser requirements.

Native checks used the shared compiler sources from `add29f2e`.
Subsequent changes affected web loading, packaging, tests and
documentation. Full integration logs are in
`/private/tmp/smalllinks-wasm/logs/`.

| Check | Result and log |
| --- | --- |
| `make test-web-runtime test-web-runtime-wasm test-web-demo` | Passed on Node 22. JavaScript passed 18 worker cases with one Wasm-only skip. Wasm passed all 19 worker cases. All 21 site checks passed with both runtimes at `/` and `/smalllinks/`, including every advertised example and guide listing, selector state, imports, Stop, timeout and startup failure recovery. `final-web-node22.log`. |
| `node /private/tmp/smalllinks-wasm/check-http.mjs` | Passed on Node 22. Thirty HTTP requests verified both loaders, Wasm MIME type and assets at `/` and `/links/`. Browser-style workers evaluated integer overflow and an imported handler example through both routes. `final-http-node22.log`. |
| `make all-ci` | Passed. `native-build.log`. |
| `./test-harness tests/handlers.tests` | All 165 cases passed. `native-handlers.log`. |
| `./test-harness tests/effect_annotations.tests` | All 76 cases passed. `native-effect_annotations.log`. |
| `./test-harness tests/native.tests` | All 76 cases passed. `native-native.log`. |
| `./test-harness tests/modules.tests` | All 67 cases passed. `native-modules.log`. |
| `./test-harness tests/typecheck_examples.tests` | All 97 cases passed. `native-typecheck_examples.log`. |
| Temporary `dune install --profile=ci` and `./tests/check-install.sh` | Passed all three installed-interpreter checks from another directory. `install.log`, `install-check.log` and `install-prefix.txt`. |
| `make rule-check`, `git diff --check 86dc2603` and documentation checks | Passed. GNU find was unavailable, so a direct scan checked tabs in changed source files. All 49 local documentation links passed. `final-rule-check.log`, `final-diff-check.log` and `final-doc-source-check.log`. |

Independent review identified a browser startup rejection that Node's
default worker error handling concealed. `a1820b4a` installs the
rejection handler before the Wasm loader. The final browser-style site
checks verify missing modules and unsupported WebAssembly, report a
startup diagnostic and recover through JavaScript. Review found no
remaining issues. Review logs are in
`/private/tmp/smalllinks-wasm-review/`.

The Node 26 site check log is
`/private/tmp/smalllinks-wasm-selector/site-tests-final.log`. The
individual runtime build and worker checks are recorded in
`/private/tmp/smalllinks-wasm-runtime/`. Packaging, workflow syntax and
asset-copy checks are recorded in
`/private/tmp/smalllinks-wasm-packaging/`.

The planning commits were `332338ab`, `65f1e661` and `86dc2603`.
Planning checks are in `/private/tmp/smalllinks-wasm-plan-decisions/`.

### Expanded guide verification

Milestone 8 is complete on `small-web`. The guide has 22 runnable
listings and the playground has seven example shortcuts. Site checks
used the source committed at `7e6fb46e`. Logs are in
`/private/tmp/smalllinks-modal-guide.qkXLEM/`.

| Check | Result and log |
| --- | --- |
| `make test-web-demo test-web-runtime` | Six Node/jsdom site checks and 15 worker checks passed. Checked example shortcuts, module links and all guide listings at the root and under a path prefix. `web-tests.log`. |
| `./links` | All 22 listings, nine linked examples and three expected type errors passed using the guide at `23b521dd`. `/private/tmp/smalllinks-web-guide-native.log`. |
| `make rule-check` and `git diff --check d1127f8d` | Passed. A direct scan covered tabs in the changed files because GNU find was unavailable. `rule-check.log` and `source-check.log`. |

### Shared source pane verification

Milestone 7 is complete on `small-web`. The playground includes file
previews in the editor pane and the guide uses the same layout with a
chapter sidebar. The checks used the source committed at `bbd33731`.
Logs are in `/private/tmp/smalllinks-workspace.dkHuTq/`.

| Check | Result and log |
| --- | --- |
| `make test-web-demo test-web-runtime` | Six Node/jsdom site checks and 15 worker checks passed. The checks cover all 17 runnable examples, all 99 file links, draft text and undo recovery, keyboard focus and Back navigation, and guide links at the root and under a path prefix. `web-tests-final.log`. |
| `make rule-check` and `git diff --check` | Passed. A direct scan covered changed files for tabs because GNU find was unavailable. `rule-check.log` and `source-check.log`. |

### Expanded catalogue and guide verification

Milestones 5 and 6 are complete on `small-web`. The
[static build](IMPL.md#build-and-serve) in `web/dist` has 17
runnable examples in five groups, 99 browsable source files and a
six-chapter guide with 11 listings that open in the playground.
The [examples and guide notes](IMPL.md#examples-and-guide) record
the source-only handler test driver.

Follow-up checks used `bf98bf32` and the integration tests and
documentation from 6.3. That revision includes the corrections from
the guide review. Logs are in `/private/tmp/smalllinks-web-followup/`.

| Check | Result and log |
| --- | --- |
| `make test-web-demo test-web-runtime` | All six Node/jsdom site checks and 15 worker checks passed. Verified all 17 runnable examples, the imported module and caller links, and every guide listing and runnable link at the root and under a path prefix. `web-tests-final.log`. |
| `./links -e` on each guide listing | All 11 values matched the guide. The import listing used `--path=examples/handlers`. `guide-snippets-final.log`. |
| `make rule-check` and `git diff --check b77c8b5f` | Passed. The GNU find tab rule was skipped, and a direct whitespace and local link scan passed. `rule-check.log`, `source-check.log`. |

### Initial demo verification

The milestone 4 checks used the source in `25352686`. Logs are in
`/private/tmp/smalllinks-web.1oRIDH/final/`. The worker used OCaml
5.4.0 and `js_of_ocaml` 6.2.0. Web checks ran in Node and jsdom.

| Check | Result and log |
| --- | --- |
| `make test-web-demo test-web-runtime` | Both site suites and all 15 worker checks passed. The site suites cover the root and a path prefix, all five examples, the guide link, highlighting, diagnostics, Stop and timeout recovery. `web-tests.log`. |
| `make all-ci` and `make tests` | Passed. 1,335 tests passed across 43 suites, with two existing ignored cases. All six scripts passed. `native-build.log`, `native-tests.log`. |
| `opam exec -- ./run-tests unit-tests` | All 105 tests passed. `unit-tests.log`. |
| Temporary `dune install`, `./tests/check-install.sh` and the installed module-import example | All three installation checks passed. The installed example returned `(0, [0, 1, 2, 3, 4])`. `install.log`, `install-check.log`. |
| `make rule-check` and `git diff --check 59ef2511` | Passed. A direct scan covered tabs and local documentation links because GNU find was unavailable. `rule-check.log`, `source-check.log`. |
