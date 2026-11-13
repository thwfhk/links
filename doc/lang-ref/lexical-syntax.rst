.. _lexical_syntax:

Lexical Syntax
==============

Identifiers
-----------

Links identifiers begin with a lowercase letter and can contain lower- and
uppercase letters, underscores, numbers, and primes ``'``.

**Valid identifiers**: ``hello``, ``helloWorld``, ``hello5``, ``hello'``, ``hello``

**Invalid identifiers**: ``5hello``, ``_hello``, ``Hello``

Literals
--------

Links supports standard base literals:

  * Strings: ``"hello"``
  * Floating point numbers: ``0.``, ``1.0``, ``1.5``
  * Booleans: ``true``, ``false``
  * Characters: ``'c'``, ``'9'``, ``'\012'``

Comments
--------

Comments are introduced by a hash symbol, ``#``, and continue for the
rest of the line.

Keywords
--------

The following keywords are reserved and are unavailable for use as identifiers::

  as case database default delete do else escape false for forall from fun
  handle if in import insert linfun module mu mutual
  orderby op open prefix query
  readonly returning set shallowhandle sig
  switch table TableHandle true typename update unsafe
  values var where with tablekeys
