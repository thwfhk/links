.. _install:

Installing SmallLinks
=====================

Use an opam switch with OCaml 5.3.0 or later. Run these commands from
the SmallLinks checkout::

  opam install .
  opam exec -- linx -e '40 + 2'

The switch stores the executable in ``bin/linx``, the prelude and
standard library in ``lib/links``, and the examples in
``share/links/examples``.

To build in the checkout, install the dependencies and run ``make``::

  opam install ./links.opam --deps-only
  make
  ./links -e '40 + 2'

See :ref:`getting_started` for file and REPL commands.
