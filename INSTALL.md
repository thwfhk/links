# Installing SmallLinks

Use an opam switch with OCaml 5.3.0 or later. From the SmallLinks
checkout, install the local package:

```sh
opam install .
opam exec -- linx -e '40 + 2'
```

The executable is `bin/linx` in the switch. It loads the prelude and
standard library from `lib/links` in the same switch. The examples are
in `share/links/examples`. Run `opam exec -- linx` for the REPL, or
pass a source file to run it:

```sh
opam exec -- linx "$(opam var share)/links/examples/extensible-case.links"
```

To build in the checkout, install the dependencies and run `make`:

```sh
opam install ./links.opam --deps-only
make
./links -e '40 + 2'
```

To install a development build in a separate directory, run the
following from the checkout with `prefix` set to an absolute path:

```sh
opam exec -- dune install --profile=dev --prefix="$prefix" links
"$prefix/bin/linx" -e '40 + 2'
```

If you place the runtime files in a separate directory, use
`--set=prelude=/path/to/prelude.links` and
`--set=stdlib_path=/path/to/stdlib` to set their locations.
