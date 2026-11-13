# SmallLinks implementation notes

Update this file as each [milestone](PLAN.md#milestones) proceeds. Record
significant choices under the relevant milestone number, with the reason
and any impact on the [language guide](SPEC.md). Put unresolved choices
under Questions for review. Once resolved, replace each question with
the decision and update the plan or spec if needed.

## Decisions from the scope review

1. Keep FreezeML. Its syntax is available without a feature flag in the
   [parser](../../core/parser.mly). The [FreezeML test config](../../tests/freezeml.config)
   selects a prelude and type display settings. Keep frozen terms and
   explicit generalisation, instantiation and term type abstraction and
   application. Keep the fixture's higher-rank and linear cases when
   removing the two session cases.
2. Keep value linearity. `linfun` and the linear arrows are part of the
   default grammar. The [type checker](../../core/typeSugar.ml) checks
   value usage independently of control-flow linearity. Keep `Lolli`,
   value kinds, usage and capture checks, and ordinary handler clause
   checks. Unrestricted resumptions can still replay a computation
   that uses a linear value; preserve this Links behaviour.
3. Delete code used only by features we remove. Remove built-in
   processes, mailboxes and XML as part of the native runtime cut.
   Enable handlers by default in the resulting interpreter.
4. **4.2–4.3.** Use the former default effect annotation rules.
   The SAT example uses `(Comp(a,{|e})) ~e~> a` to share its effect tail.

5. **4.3.** Keep `~>` and the related `wild` arrows, including the
   linear forms. They give short signatures for recursive calls and
   primitives that use `wild`.
6. **4.3.** Keep both labelled field spellings, `x:T` and `x{:T}` for
   presence and `x-` and `x{-}` for absence. Keep `x{p}` for a presence
   variable and `|r` for a row tail. Keep standalone presence arguments
   such as `{:T}` and `{-}`, and keep `_` and `%` for anonymous rigid
   and flexible variables. Keep nullary variant labels and `Ask:Int`
   as shorthand for `Ask:() => Int`. Preserve explicit recursive
   types and rows.

## Keep the existing compiler path

1. [`bin/driver.ml`](../../bin/driver.ml) threads the compiler context
   from the loader or parser through [`Frontend`](../../core/frontend.ml),
   [`Sugartoir`](../../core/sugartoir.ml), [`Backend`](../../core/backend.ml)
   and [`Evalir`](../../core/evalir.ml). Files, `-e` and interactive
   sentences enter through different driver functions. Test all three.
2. Keep the effect desugaring in [`desugarEffects.ml`](../../core/desugarEffects.ml).
   It expands operation signatures and resolves anonymous row tails.
   Keep the module, datatype, function and pattern passes on the
   native path.
3. Keep closure conversion and [`BuildTables`](../../core/buildTables.ml).
   The interpreter looks up function bodies and uses the continuation
   variable table to save locals. Remove entries used only to serialise
   web state after their callers are gone.
4. Operation calls and handlers lower to `Ir.DoOperation` and
   `Ir.Handle`. Keep `Value.Eff_Handler_Continuation` in
   [`value.ml`](../../core/value.ml), including ordinary trap lookup
   and deep and shallow resumption. Keep `Ir.CallCC` for `escape`.

## Remove native runtime dependencies in order

At each cut, update [`prelude.links`](../../prelude.links),
[`lib.ml`](../../core/lib.ml) and [`defaultAliases.ml`](../../core/defaultAliases.ml)
before dropping syntax and types they use. Startup parses the primitive
signatures, then compiles and evaluates the prelude. Keep the list
library and handler helpers `Maybe`, `Either`, `Comp`, `Zero` and
`gen0`–`gen2`. The list library uses `unsafe sig` for its current effect
signatures; the `gen` helpers use effect upcasts.

1. **2.1.** `make no-db` is an alias of `make all` now that the MySQL,
   PostgreSQL and SQLite driver packages are gone. The database test
   targets required those drivers, so their source fixtures stay in
   the tree for milestone 3 with the runners and build stanzas removed.
   The native IR unit runner remains available. The shared database
   loader and query code remain in the compiler until milestone 3.
2. **2.2.** Files and `-e` use the native driver. The REPL keeps its
   separate module renaming setting. Remove `alien`, the `client` and
   `server` function annotations, the web and JavaScript CLI modes, and
   the route and HTTP response primitives that provided web entry
   points from Links source. Former location keywords become ordinary
   identifiers. Keep internal locations while XML and process code
   still uses them. The retained page tests use `renderPage` directly.
   In **2.3**, remove XML, formlets and pages, including the browser
   backend and JavaScript library. The native driver uses `Evalir.Eval`
   directly. Keep the ordinary state and `Maybe` combinators and the
   `Either` alias from the former formlet section of the prelude.
   Without XML literals, the lexer handles angle brackets as ordinary
   operators, including the brackets in handler patterns. The process
   runtime still contains WebSocket and serialisation code, due for
   removal in 2.5.
3. **2.4.** Remove session kinds, types, primitives, CP, and the special
   handling of `SessionFail`. `SessionFail` can now be handled and
   resumed as an ordinary operation. Rows store their field map and
   tail variable. Aliases and recursive applications drop their dual
   flags. `Mono` now checks the `Mono` restriction, which accepts a
   record of monomorphic fields and rejects a frozen polymorphic
   function in the new FreezeML cases. Retained linearity fixtures use
   linear closures in place of channels.
4. **2.5.** The native evaluator keeps Lwt and pauses every 100 steps at
   the former scheduler yield points to bound OCaml stack use.
   `ApplyPure` evaluates with an empty continuation and returns its
   value. Function definitions and continuation local variables still
   use the tables built by `BuildTables`. Request data, serialisation
   and the tables used only by serialisation are gone. The source
   `Location` type is gone. The compiler's function location field
   remains and uses its existing `Unknown` value for native functions.
   Keep Yojson for the shared database loader until milestone 3.
   Retained mailbox fixtures use algebraic operations and handlers.
5. **3.1.** Remove lens syntax, inference, IR and evaluation, the lens
   library, `Serial` and `isNew` from the prelude, and the statistics
   primitives. Lens keywords such as `lens` and `lensget` become
   ordinary identifiers. The table and query paths still build in 3.1.
6. **3.2.** Remove database declarations, tables, query blocks, database
   updates and temporal syntax from the source language and IR. A list
   generator now holds a pattern and source expression. Keep
   `sortByBase` in [`DesugarFors`](../../core/desugarFors.ml) and the
   `Base` restriction used by `orderby`. The lexer treats `<-t-` and
   `<-v-` as whole operators so they cannot start a list generator.
   The old query modules still build after dropping their references
   to the deleted IR constructors. Remove those modules in 3.3.
7. **3.3.** Remove `sparql`, the query modules, the database loader,
   internal database values and the settings and libraries they used.
   The IR unit test runner uses no database configuration. Keep
   `calendar` and the user timestamp parser for ordinary dates.
   The REPL keeps `Dynlink` for its `@dload` command.

## Preserve inference as features go

1. Work through [`parser.mly`](../../core/parser.mly),
   [`sugartypes.ml`](../../core/sugartypes.ml), the sugar traversals,
   [`commonTypes.ml`](../../core/commonTypes.ml), [`types.ml`](../../core/types.ml),
   [`typeSugar.ml`](../../core/typeSugar.ml) and the matching IR types,
   traversals and checker. Update interfaces and printers with the
   shared types. Preserve ordinary row unification, including open rows,
   field presence and `Eff` restrictions.
2. Remove session row duality with sessions. Keep `linfun`, `-@`,
   `~@`, and `~linfun`. Adapt recursive alias linearity tests that
   currently use `End` to use a linear function type. Keep accepted
   and rejected uses of linear values in the native tests.
3. **4.1.** Remove control-flow linearity, including `lindo`, `xlin`,
   the operation-specific `=@` arrow and the `Lin` kind shorthand.
   `lindo` and `xlin` are ordinary identifiers. Operations still have
   a distinct internal type with an argument tuple and result type.
   Resumptions use the ordinary function type. Handler input and
   output rows use the former default kinds. The printer uses full
   kinds for effect presence variables, such as `Presence(Unl,Eff)`.
4. Keep `DesugarEffects` on both user code and primitive signatures.
   Required work includes resolving anonymous effect variables,
   elaborating operation types and checking alias kinds. Keep the
   effect upcasts and flexible row variables used by `gen0`–`gen2`.
5. **4.2.** Add explicit row parameters to the handler example aliases.
   The migrated signatures name shared tails and presence variables
   where the optional policy supplied them. `Fringe.step` keeps its
   separate continuation tail. The handler example runner now calls
   the SAT assertions and is included in the example type checks.
6. **4.3.** Remove implicit sharing, automatic presence insertion and
   implicit alias arguments. `DesugarEffects` uses declared alias kinds
   when elaborating type alias arguments and resolves anonymous row
   tails in the same pass. Alias bodies, including `effectname`, check
   for unbound anonymous tails before conversion to internal types.
   The default printer uses `~` for `wild:()` in an arrow, preserves
   `wild:()` in row arguments, and prints quantifier kinds in a form
   accepted by the parser. Keep the other display settings and printer
   engines.

## Keep build and test files in step

1. Update Dune stanzas, `dune-project`, opam templates and regenerated
   package files as their dependencies disappear. Check the Makefile,
   native CI, install rules, `preinstall/` and `linkspath/`. Keep the
   launcher used by `test-harness` and the paths to the retained prelude
   and standard library.
2. Split mixed suites case by case. `records` and `roundtrippable_types`
   have table cases; `functions` and `polymorphism` have mailbox cases;
   keep the FreezeML cases in `polymorphism`. `typed_ir` and frontend
   rechecking cover both retained and removed features. Replace probes
   that still serve a purpose: for example, use an algebraic operation
   in place of `recv()` to test effects in a type alias.
3. Keep `examples/handlers/tests.links` and the files it imports.
   Update `tests/typecheck_examples.tests` alongside example deletions;
   the registration check requires an entry for every tracked `.links`
   example. Remove feature-only suites, configs and runners after
   moving any retained cases. Update the native IR unit test runner
   when its database configuration sample goes.

## Verify the subset

1. **5.1.** Handlers are on by default. Keep `enable_handlers` and
   `--enable-handlers` as existing controls. The default evaluator uses
   handler continuations, including for `escape`. The explicit off
   setting still selects the pure evaluator. Test both settings.
2. **5.2.** Dune installs the prelude, standard library and examples
   directly. The executable resolves paths from its real location.
   Use `lib/links` under the install prefix and `lib` next to the build
   tree's `bin` directory. An explicit `--config` takes precedence over
   `LINKS_CONFIG`, then an existing `etc/links/config` in the prefix.
   Keep the prelude and standard library settings. The install check
   runs the executable from a separate directory and loads both.
   The source launcher is `./links`, the installed command is `linx`,
   and the package name is `links`. Use `make` for a development build
   and `./run-tests unit-tests` for the native IR tests.
3. **5.3.** The Church numeral example uses closed `wild` arrows to
   match its call contexts, including the top level. The quantified
   encoding stays the same. Check the guide's examples using the same
   compiler as the final regression suite.

## Baseline fixtures to migrate

1. Move tests for ordinary linear functions and generalisation from
   the session and control-flow linearity suites to retained suites.
   In 4.1, move the value subkinding cases into
   [`functions.tests`](../../tests/functions.tests) and the ordinary
   operation and value-linearity cases into
   [`handlers.tests`](../../tests/handlers.tests).
2. In 3.2, move the ordinary list generator and range tests into
   [`collections.tests`](../../tests/collections.tests). The former
   `asList` case in [`typed_ir.tests`](../../tests/typed_ir.tests) uses
   a list comprehension, and the Base row case uses lists of records.
3. Keep native tests from mixed suites. `booleans` uses `javascript`,
   `lexing` has XML cases, `modules` has a foreign import, and
   `continuations` has an escape that crosses process boundaries.
   Keep tests for equivalent native behaviour where they still apply.
