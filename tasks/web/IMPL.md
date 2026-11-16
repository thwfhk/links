# SmallLinks web demo implementation notes

The [plan](PLAN.md) records scope, milestones and checks. Record
significant decisions here as they are made, with links to the
corresponding checks.

## Build and serve

Install the [native build dependencies](../../INSTALL.md) and Node.js
18 or later. Run these commands from the repository root.

```sh
opam install js_of_ocaml-lwt
npm --prefix web ci
make web-demo
python3 -m http.server 8000 --bind 127.0.0.1 --directory web/dist
```

Open `http://127.0.0.1:8000/`. The build puts the complete static site
in `web/dist`. Serve that directory over HTTP for local use or copy
its contents to a static host. All assets use paths relative to the
site, so it can also be served under a path prefix.

`make test-web-demo` builds the site and exercises it in Node with a
simulated DOM and the compiled SmallLinks worker.

## Runtime

The [native CLI](../../bin/driver.ml) and
[browser worker](../../web/runtime/worker.ml) share
[the driver phases](../../core/driverRuntime.ml). Both load the
comprehension helpers and prelude. Check returns the inferred type from
the frontend. Run continues through IR compilation and evaluation.

The native executable owns Linenoise and `Lwt_main.run`. The worker
uses the same evaluator with `js_of_ocaml-lwt` to schedule its
periodic pauses. Each evaluation keeps its move observations and pause
counter in its Lwt context. The native driver cancels a pending
evaluation after an interrupt so it can account for reads before it
recovers the prompt. [Evaluator](../../core/evalir.ml)
· [Lwt browser integration](https://ocsigen.org/js_of_ocaml/latest/js_of_ocaml/lwt.html).

The [Dune rule](../../web/runtime/dune) uses `js_of_ocaml --file` to
embed the prelude, comprehension helpers, standard library and example
sources in its virtual filesystem. The worker and public source
catalogues obtain the example paths from
[`tests/typecheck_examples.tests`](../../tests/typecheck_examples.tests).
The existing module loader searches the embedded standard library and
the selected example's directory. For an edited example, the worker
updates the virtual entry file before checking.
[Module lookup](../../core/moduleUtils.ml#L29).

Run these commands from the repository root with OCaml 5.3 or later.
The worker checks also use Node.js.

```sh
opam install js_of_ocaml-lwt
make web-runtime
make test-web-runtime
```

The standalone script is `_build/default/web/runtime/worker.js`.

### Browser limits

- Output comes from `print` and is capped at 64 KiB or 1,000 nonempty
  chunks per request. The worker sends a truncation notice if it
  discards output.
- `exit(v)` returns the supplied value. `sysexit(n)` ends the request
  with status `n` and preserves preceding output. The prelude uses
  `sysexit` for failed assertions.
- The browser uses 32-bit `Int` values. `serverTimeMilliseconds()`
  reports an unsupported operation because the current epoch time in
  milliseconds exceeds that range.
- Raw TCP and native bcrypt report unsupported operations. The
  `js_of_ocaml` linker warns about native Unix and bcrypt primitives.
  The worker guards the corresponding SmallLinks calls and skips native
  startup and configuration.

[Primitives](../../core/lib.ml) · [Prelude](../../prelude.links#L741)
· [js_of_ocaml integer representation](https://ocsigen.org/js_of_ocaml/latest/js_of_ocaml/runtime-representation.html#integers).

## Worker interface

| Direction | `kind` | Other fields |
| --- | --- | --- |
| Worker to page | `ready` | The worker can accept source. |
| Page to worker | `check` or `run` | `id`, `source` (the current editor text) and optional `exampleId` (a bundled repository-relative source path). |
| Worker to page | `output` | `id`, `text`. Chunks are sent in order. |
| Worker to page | `success` | `id` and `inferredType` for Check. Run also includes `value`. Early exit includes only `id` and the printed `value`. |
| Worker to page | `failure` | `id`, `stage` (`startup`, `parsing`, `checking` or `running`), plain-text `diagnostic` with its location when available, and optional `exitStatus`. |

A new buffer uses a fixed name for diagnostics. An example uses its
repository path, and the editor text replaces that example's entry
file for the request. The page renders output and diagnostics as text.
It handles worker startup errors and timeouts using the active request
ID.

Start a fresh dedicated worker for each request so that definitions
and mutable compiler state cannot leak across submissions. Allow one
active request and terminate its worker on Stop or timeout. The page
timer also covers worker startup and synchronous type checking. Keep
the editor and any output already received.
[Worker termination](https://html.spec.whatwg.org/multipage/workers.html#dom-worker-terminate-dev).

## Editor and highlighting

The [playground](../../web/playground/index.html) starts with a
labelled text area. [The editor module](../../web/playground/editor.js)
upgrades it to CodeMirror 6 and uses its `StreamLanguage` extension for
highlighting. Its tokeniser follows the SmallLinks
[lexer conventions](../../core/lexer.mll) for keywords, `#` comments,
literals and operators. The build bundles the editor dependencies
locally.
[CodeMirror language package example](https://codemirror.net/examples/lang-package/).

TryLinks combines an editor with Links tutorials. The OCaml Playground
uses CodeMirror and a browser worker, with a file-style editor and a
result panel. Use these as references for the page interaction.
[TryLinks paper](https://arxiv.org/abs/1905.02033)
· [OCaml Playground source](https://github.com/ocaml/ocaml.org/blob/main/playground/src/main.ml).

## Examples and guide

The [example catalogue](../../web/build/examples.mjs) groups runnable
examples by topic and writes them to `examples.json`.
`sources.json` indexes the registered examples and bundled library
files for the source viewer. The build copies the indexed files
byte for byte. The source metadata records import names and file
paths, including
[`module_import.links`](../../examples/handlers/module_import.links)
and its [`Shallow_state` module](../../examples/handlers/shallow_state.links).
Record any new cross-file example imports in the catalogue so the
viewer can link both the dependency and its caller.

The [handler test driver](../../examples/handlers/tests.links) is
deferred. Its [random π estimate](../../examples/handlers/pi.links)
exceeded 60 seconds in the browser worker. The short module import
example exercises its shallow state handler within the demo timeout.

The [playground](../../web/playground/index.html) shows a directory tree
and example shortcuts in its sidebar. It shows the directories under
`examples/met` directly under `examples`, with `thesis` labelled
`met-thesis`.
The `file` parameter opens the source pane in read-only mode. Following
imports and callers keeps the current draft available through **Return
to editor**. **Load into playground** makes the displayed source editable
and enables checking and running. Files under `examples/` keep their
original path and import context. Bundled library files and the prelude
load as editor text.

The [guide renderer](../../web/build/guide.mjs) renders the concise
[web guide](../../web/guide.md) at build time with Markdown-it. It
generates a chapter sidebar and links to repository examples and
browsable sources. A standalone listing opens the editor
with its exact source in the `code` parameter. A listing that imports
a module uses the `example` parameter to retain the entry file and
its imports.
