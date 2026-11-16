# SmallLinks web demo implementation notes

The [plan](PLAN.md) records scope, milestones and checks. Record
significant decisions here as they are made, with links to the
corresponding checks. The design below is the starting point for the
browser build.

## Runtime

Add a browser build of the OCaml checker and interpreter using a Dune
JavaScript target. Reuse the [driver phases](../../bin/driver.ml#L156)
to initialise the primitive environment, load the comprehension helpers
and prelude, and process a submission. The checker returns its result
after [the frontend](../../core/frontend.ml#L196). Run lowers the checked
program to IR, applies the existing IR passes and invokes the
interpreter. [Dune's JavaScript compilation guide](https://dune.readthedocs.io/en/stable/jsoo.html)
describes the build target.

The [core library](../../core/dune) currently depends on Linenoise,
`lwt.unix` and Safepass. Keep terminal input, native configuration
and executable-relative asset discovery with the native entry point.
Reuse the evaluator's `Lwt.t` computation and its stack breaks in the
worker. Keep `Lwt_main.run` on the native side and preserve the
evaluator's cleanup and early-exit handling. [Evaluator](../../core/evalir.ml#L304)
· [Lwt browser integration](https://ocsigen.org/js_of_ocaml/latest/js_of_ocaml/lwt.html).

The browser link test should also exercise type printing and diagnostics,
which use [domain-local storage for effect names](../../core/modalEffects.ml#L63).

Bundle `prelude.links`, `lib/comprehension.links`, the importable
standard library and the dependencies of published examples. Resolve
imports from this bundle using the existing module loader with browser
paths or a source resolver. Report a missing module by name. A virtual
path in a request or diagnostic refers to a packaged source or the
submitted program. [Module lookup](../../core/moduleUtils.ml#L28).

Send `print` output to the page. Use a browser diagnostic when a program
calls a primitive that requires an unavailable host facility, such as
access to the local filesystem or raw TCP. Preserve user-defined effects,
handlers and the language-level `exit(v)` behaviour. Give `sysexit(n)`
a browser implementation that ends the request with status `n` and
preserves output. The prelude calls it on assertion failure. Reuse the
current type and value printers and plain-text error formatting.
[Primitives](../../core/lib.ml) · [Prelude](../../prelude.links#L741)
· [Diagnostics](../../core/errors.mli).

## Worker interface

| Direction | Message | Contents |
| --- | --- | --- |
| Worker to page | Ready | The worker can accept source. |
| Page to worker | Check or Run | Request ID, current editor text, and optional example ID to select bundled imports and the source name. |
| Worker to page | Output | Request ID and a chunk of printed text, in order. |
| Worker to page | Success | Request ID and the inferred type for Check. For Run, the printed result and type on normal return, or the value passed to `exit(v)` on early exit. |
| Worker to page | Failure | Request ID, stage (parsing, checking or running), plain-text diagnostic, and source location or exit status when available. |

A new buffer uses a fixed name for diagnostics. An example uses its
repository path, and the editor text replaces that example's entry
file for the request. Resolve an example ID through the packaged
catalogue. The page renders output and diagnostics as text. It handles
worker startup errors and timeouts using the active request ID.

Start with a fresh dedicated worker for each request so that definitions
and mutable compiler state cannot leak across submissions. Allow one
active request and terminate its worker on Stop or timeout. The page
timer also covers worker startup and synchronous type checking. Bound
the amount of printed output presented by the page. Keep the editor
and any output already received. [Worker termination](https://html.spec.whatwg.org/multipage/workers.html#dom-worker-terminate-dev).

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

Generate a small example catalogue from repository paths. Begin with
[factorial](../../examples/factorial.links),
[single yield](../../examples/met/fresco-effects/single-yield.links),
[rank-two polymorphism](../../examples/met/fresco-types/rank-two.links)
and [handler search](../../examples/met/fresco-effects/find_mask_paper.links).
Exercise packaged module lookup with the
[handler test driver](../../examples/handlers/tests.links) and its
sibling modules. Carry each example's source and dependencies through
the build from their original files.

Render [the guide](../met/GUIDE.md) at build time. Preserve its table
of contents, heading anchors, tables and fenced code blocks. Map
links to bundled examples to the corresponding playground entry and
resolve other repository links to their source pages. Put any
browser-specific instructions alongside the guide in the web build.
The guide's [two-file import example](../met/GUIDE.md#modules-and-imports)
needs both snippets if it is offered as a runnable example.

## Questions for review

1. SmallLinks uses OCaml `int`, which `js_of_ocaml` represents as
   32-bit integers. Check the range, arithmetic at its boundaries and
   the result of `serverTimeMilliseconds()`, whose current epoch
   millisecond value exceeds that range. Decide which browser differences
   to document and which primitives need adaptation before inclusion.
   [Runtime representation](https://ocsigen.org/js_of_ocaml/latest/js_of_ocaml/runtime-representation.html#integers)
   · [Time primitives](../../core/lib.ml#L424).
2. Check Safepass's bcrypt dependency in the browser build. Decide
   whether it can be bundled directly or needs an unsupported-primitive
   diagnostic for this release. [Cryptography primitives](../../core/lib.ml#L742).
