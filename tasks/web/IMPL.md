# SmallLinks web demo implementation notes

The [plan](PLAN.md) records scope, milestones and checks. Record
significant decisions here as they are made, with links to the
corresponding checks. The design below is the starting point for the
browser build.

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
sources in its virtual filesystem. The existing module loader searches
the embedded standard library and the selected example's directory.
For an edited example, the worker updates the virtual entry file before
checking. [Module lookup](../../core/moduleUtils.ml#L29).

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

Use a labelled text area for the first working page.
CodeMirror 6 is a candidate for optional highlighting. Its
`StreamLanguage` extension supports a small tokenizer. Use SmallLinks
[lexer conventions](../../core/lexer.mll) for keywords, `#` comments,
literals and operators, and check effect declarations, handler clauses
and modality delimiters on repository examples. Test escaped strings
and comments. Bundle the editor dependencies locally if this option
is used.
[CodeMirror language package example](https://codemirror.net/examples/lang-package/).

TryLinks combines an editor with Links tutorials. The OCaml Playground
uses CodeMirror and a browser worker, with a file-style editor and a
result panel. Use these as references for the page interaction.
[TryLinks paper](https://arxiv.org/abs/1905.02033)
· [OCaml Playground source](https://github.com/ocaml/ocaml.org/blob/main/playground/src/main.ml).

## Examples and guide

The [example catalogue](../../web/build/examples.mjs) uses these source files.

- [Factorials](../../examples/factorial.links)
- [Single yield](../../examples/met/fresco-effects/single-yield.links)
- [Rank-two polymorphism](../../examples/met/fresco-types/rank-two.links)
- [Search with effect handlers](../../examples/met/fresco-effects/find_mask_paper.links)
- [Import a state handler](../../examples/handlers/module_import.links)

The build copies each source and the
[imported state handler](../../examples/handlers/shallow_state.links)
byte for byte. The runtime embeds their module sources.

The [handler test driver](../../examples/handlers/tests.links) is
deferred. Its [random π estimate](../../examples/handlers/pi.links)
exceeded 60 seconds in the browser worker. The short module import
example exercises its shallow state handler within the demo timeout.

[The guide renderer](../../web/build/guide.mjs) renders
[the guide](../met/GUIDE.md) at build time with Markdown-it. It
preserves the table of contents, heading anchors, tables and fenced
code blocks. The search example opens in the editor. Other repository
links point to the corresponding `small-met` source pages.
