.. _getting_started:

Getting started
===============

You can run Links programs from the command line or try expressions in the REPL.

Running the REPL
----------------

The Links REPL (Read-Eval-Print-Loop) allows you to run commands and evaluate
expressions interactively. Typing ``linx`` on a terminal should bring up an
interactive window::

   _     _ __   _ _  __  ___
  / |   | |  \ | | |/ / / ._\
  | |   | | , \| |   /  \  \
  | |___| | |\ \ | |\ \ _\  \
  |_____|_|_| \__|_| \_|____/
  Welcome to Links version 0.9 (Burghmuirhead)
  links>

You can now write an expression, and Links will show you the result. Note that
in interactive mode, each expression must be terminated with a semicolon.

::

  links> 1 + 2 + 3;;
  6 : Int

The Links REPL includes directives, which allow you to perform operations such
as loading a file or showing the current type environment. To show all available
directives, type ``@directives;``.

A useful directive is to load in a Links file, which populates the environment
with all functions defined in the file. To see this, create a file called
``helloWorld.links``::

  fun sayHello() {
    print("Hello, world!")
  }

Now, from within a REPL, type ``@load "helloWorld.links";``, and then type
``sayHello()``. You should see ``Hello, world!`` printed to the console::

   _     _ __   _ _  __  ___
  / |   | |  \ | | |/ / / ._\
  | |   | | , \| |   /  \  \
  | |___| | |\ \ | |\ \ _\  \
  |_____|_|_| \__|_| \_|____/
  Welcome to Links version 0.9 (Burghmuirhead)
  links> @load "helloWorld.links";
  () : ()
  links>
  ...... sayHello();
  Hello, world!() : ()
  links>

To exit the REPL, either press ``Ctrl-D`` or enter ``@quit;``.

Running files
-------------

You are likely to want to run Links files from the command line, rather than
from the REPL. Links files consist of a series of bindings, optionally followed
by an expression. As an example, change ``helloWorld.links`` to::

  fun sayHello() {
    print("Hello, world!")
  }
  sayHello()

Now, you can run the file from the command line::

  $ linx helloWorld.links
  Hello, world!() : ()

Running the examples
--------------------

As described in :ref:`install`, the environment variable ``$OPAM_SWITCH_PREFIX``
points to the currently-active OPAM switch, and the example Links programs are
installed into ``$OPAM_SWITCH_PREFIX/share/links``.

Run the pattern matching example from a terminal::

  $ linx "$OPAM_SWITCH_PREFIX/share/links/examples/extensible-case.links"

Use the ``--path`` flag to add directories where Links should look for modules.
