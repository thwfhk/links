# Installing Links

We recommend installing Links using the OPAM tool (version >= 2.1), available from [opam.ocaml.org](https://opam.ocaml.org/).

Links requires at least OCaml 5.1.1 to build and install. Therefore
you should first install the minimum (or greater) required version of
OCaml:

```
$ opam switch create 5.1.1
```

You can then install Links:

```
$ opam install links
```

This will put Links and its files into your OPAM switch. The
environment variable `$OPAM_SWITCH_PREFIX` points to your current
active switch. Links files install to several locations inside an OPAM
switch:

* The executable is called `linx` and goes into `$OPAM_SWITCH_PREFIX/bin`
* The Links prelude and standard library go into `$OPAM_SWITCH_PREFIX/lib/links`
* The example Links programs go into `$OPAM_SWITCH_PREFIX/share/links`
* Links configuration file goes into `$OPAM_SWITCH_PREFIX/etc/links`

# Running Links

Run `linx` for the REPL, pass `-e` to evaluate an expression, or pass a
source file to run it.

```
$ linx -e '40 + 2'
42 : Int
$ linx "$OPAM_SWITCH_PREFIX/share/links/examples/extensible-case.links"
```

# Documentation

Some (outdated) documentation can be built by running the Makefile in
the doc directory.

Some very incomplete documentation is available on the links wiki:

  https://github.com/links-lang/links/wiki
