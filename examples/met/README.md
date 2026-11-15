# Modal effect and Fresco examples

Build SmallLinks with `make`. From the repository root, run a file
with `./links`, for example:

```sh
./links examples/met/thesis/handlers.links
./links examples/met/fresco-programs/unix.links
```

For an installed interpreter, use `linx` and the files under
`share/links/examples/met` in the installation prefix. The examples
use the standard prelude.

- [Thesis tutorial](thesis) starts with pure functions and introduces
  effect interfaces, handlers, modal callbacks and the absolute kind.
- [Fresco effect tests](fresco-effects) show inference with effectful
  callbacks, operation parameters and higher-order operations.
- [Larger Fresco programs](fresco-programs) simulate Unix processes and
  elaborate a small dependently typed object language.
- [Fresco type tests](fresco-types) show first-class polymorphism,
  application and freezing. They include both native and Church-encoded
  list examples.

Files under `rejected/` are examples of type errors. Their first
comments describe the expected rejection. To check them from the
repository root, run `./test-harness tests/typecheck_examples.tests`.
To check the runtime results, run `./test-harness tests/met_examples.tests`.
The runtime suite omits the example under `blocked/`. It runs with
default settings and reports `Type abstraction needs a type annotation`
with `--set=recheck_frontend_transformations=true`.

The examples come from the Maetel tutorial in Wenhao Tang's thesis
(`chapters/overview.tex`) and the README and tests of Aghilas
Y. Boussaa's Fresco implementation.

In the source checkout, see the [language guide](../../tasks/met/GUIDE.md)
for the SmallLinks syntax, the
[source inventory](../../tasks/met/examples.md#example-source-coverage)
for the expected results and deferred examples, and the
[example notes](../../tasks/met/example-issues.md) for reproductions.
