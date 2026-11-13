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
* The Links prelude and JavaScript libraries go into `$OPAM_SWITCH_PREFIX/lib/links`
* The example Links programs go into `$OPAM_SWITCH_PREFIX/share/links`
* Links configuration file goes into `$OPAM_SWITCH_PREFIX/etc/links`

# Running Links.

Links supports running applications via a standalone application
server.

## Examples

To run the examples that don't use the database with the Links
application server issue the following command:
```
$ linx --path=$OPAM_SWITCH_PREFIX/share/links/examples --path=$OPAM_SWITCH_PREFIX/share/links/examples/games $OPAM_SWITCH_PREFIX/share/links/examples/webserver/examples-nodb.links
```
(This version just displays the source code for examples that use the
database.)

The default port is 8080, so you should now be able to access the
examples by pointing your browser at:

  http://localhost:8080/

# Documentation

Some (outdated) documentation can be built by running the Makefile in
the doc directory.

Some very incomplete documentation is available on the links wiki:

  https://github.com/links-lang/links/wiki
