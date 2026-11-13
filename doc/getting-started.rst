.. _getting_started:

Getting started
===============

In this section, we will see how to get up and running with the Links REPL, as
well as running the web examples.

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
installed into into ``$OPAM_SWITCH_PREFIX/share/links``.

To run the examples, run the following command at a terminal::

  $ linx -m --path=$OPAM_SWITCH_PREFIX/share/links/examples:$OPAM_SWITCH_PREFIX/share/links/examples/games $OPAM_SWITCH_PREFIX/share/links/examples/webserver/examples-nodb.links

The ``-m`` flag enables modules, and the ``--path`` flag sets the path of where
to look for Links files.

You should then be able to run the (non-database) examples by visiting
``http://localhost:8080`` in a web browser.
