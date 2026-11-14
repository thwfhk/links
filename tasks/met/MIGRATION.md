# Modal effect migration inventory

This inventory starts from `21348680`, after removal of `unsafe_cast`,
and includes the handler runtime fixtures for milestone 1.4. See [the
migration criteria](SPEC.md#migration-and-deferred-coverage) and
[milestones 2 and 5](PLAN.md#milestones).

- **Translate**: preserve the checked behaviour and update types,
  declarations or printed expectations.
- **Change expectation**: keep the case or its purpose and change what
  it accepts, rejects or checks under the approved rules.
- **Defer**: keep a named record of the postponed feature the original
  case needs. A row tail used in several types can usually become one
  ambient context. Optional instances of a known interface need a
  separate review from unknown effect contexts.

Classifications for translations describe what to check during migration.
In particular, check the higher-order operation payloads and resumption
types with the modal checker before changing any registration.

## Native primitives and type aliases

The table covers all 103 active entries in [core/lib.ml](../../core/lib.ml)
and includes signatures built by OCaml helpers. Classify the native
permission from what the primitive does. Keep the existing IR
`PURE`/`IMPURE` flag for `ApplyPure` independent of this permission.

| Entries | Classification and migration |
| --- | --- |
| `max_int`, `min_int`, `infinity`, `neg_infinity`, `forever`, `beginningOfTime` | Translate: retain the base types. |
| `Nil` | Translate: `List a`. |
| `+`, `-`, `*`, `/`, `^`, `mod`, `+.`, `-.`, `*.`, `/.`, `^.`, `^^`, `==`, `<>`, `<`, `>`, `<=`, `>=`, `not`, `negate`, `negatef` | Translate: pure arithmetic, comparison and concatenation. Preserve the runtime failure of integer division and modulo by zero. |
| `intToString`, `stringToInt`, `intToFloat`, `floatToInt`, `floatToString`, `stringToFloat` | Translate: pure conversions. Remove the fresh effect-row quantifier made by `conversion_op`; retain runtime failures for invalid input. |
| `Cons`, `Concat`, `hd`, `tl`, `$$hd`, `$$tl`, `length`, `Sum`, `take`, `drop`, `max`, `min`, `intRange`, `$$intRange` | Translate: pure list operations. Use `List` and the new result variant syntax for `max` and `min`. Retain the failure of head and tail on empty lists and the internal names used in pattern and range lowering. |
| `least`, `greatest`, `dateToInt`, `intToDate`, `dateYear`, `dateDay`, `dateMonth`, `dateHours`, `dateMinutes`, `dateSeconds`, `dateMilliseconds`, `showUTC` | Translate: pure operations on supplied dates, timestamps and UTC offsets. Preserve the errors at infinite dates where applicable. |
| `ord`, `chr`, `floor`, `ceiling`, `cos`, `sin`, `tan`, `log`, `log10`, `exp`, `sqrt`, `tilde`, `ltilde`, `stilde`, `charAt`, `strsub`, `strlen`, `strescape`, `strunescape`, `strContains`, `implode`, `explode`, `verify` | Translate: pure functions of supplied arguments. Migrate the list types of `ltilde`, `implode` and `explode`. |
| `print`, `debug`, `sysexit`, `serverTime`, `serverTimeMilliseconds`, `now`, `utcOffset`, `parseDate`, `show`, `random`, `gensym`, `getArgs`, `crypt` | Translate to `[wild]`. `parseDate` uses the local time zone when the input omits an offset; `show` uses it for dates, including dates in containers. `getArgs` reads process arguments. `crypt` supplies no seed to `Bcrypt.hash`, which reads `/dev/urandom`. `now`, `random` and `gensym` use bare arrows today. |
| `connectSocket`, `writeToSocket`, `readFromSocket`, `closeSocket` | Translate to `[wild]`; migrate the `Nothing`/`Just` result types of `connectSocket` and `readFromSocket`. |
| `exit` | Change expectation: `forall a::Abs,b. [wild] ((a) -> b)`. Retain its runtime continuation and independent result instantiation. Check an absolute argument and reject an ambient function argument. |
| `error`, `sleep` | `error` is a pure, deterministic failure. `sleep` requires `[wild]` for timing and currently reports that it is unimplemented. |
| `List`, `Socket`, `Repeat`, `Regex` | Translate: reserve the built-in `List` constructor and preserve `Socket` in [core/defaultAliases.ml](../../core/defaultAliases.ml). Migrate both variant strings in [core/linksregex.ml](../../core/linksregex.ml), including the recursive `Regex` type and its nested `Repeat` variant. |

## Preludes and standard library

The [default prelude](../../prelude.links) has 84 explicit signatures
and five type aliases. This table also names inferred definitions whose
dependencies or types matter during migration. Default pure global
signatures have an outer `[]`; same-context callbacks have ambient
arrows. A supplied pure function can carry its own `[]` when needed.

| Definitions | Classification and migration |
| --- | --- |
| `concatMap`, `map`, `filter`, `iter`, `sortBy`, `sortByBase`, `all`, `any`, `fold_left`, `fold_left1`, `fold_right`, `fold_right1`, `mapi`, `span`, `takeWhile`, `dropWhile`, `search`, `find`, `partition`, `concatMapKey`, `groupBy`, `groupByMap`, `aggBy`, `groupByFlat`, `$` | Translate callback and invocation arrows together. Keep the `Base` data-row constraint of `sortByBase`. `find` calls `error`; apply its native permission decision. Check `concatMap` for comprehension desugaring. |
| `flip`, `curry`, `uncurry`, `compose`, `-<-`, `->-`, `lf`, `applyE` | Translate functions returning or storing callbacks. Each body uses one invocation context. Preserve `lf`'s linear result arrow and `applyE`'s callback inside `Maybe`. |
| `State`, `runState`, `>>=`, `return`, `fmap`, `sequence` | Translate: `State(d,a)` contains a pure state function. Keep that fixed context on returned and stored state computations and on the pure callbacks required by `>>=` and `fmap`. |
| `Maybe`, `Either`, `Zero`, `isJust`, `fromMaybe`, `pureE` | Translate the data types and their uses; preserve constructors and pattern syntax. |
| `Comp(a,e)` | Translate each use: bare thunk for one shared invocation context, an absolute thunk for a fixed context, and a relative thunk when a handler supplies the added interface. Defer the general alias taking an effect argument. |
| `gen0`, `gen1`, `gen2` | Change expectation: the row-generalising coercions are replaced by a pure function type `[] T` and application where its absolute requirement holds. Preserve arities and result values at the use sites: `handlers.tests` Generalise (1–2), SAT's `parseTextExpression` and `parse`, and fringe's `sameFringe`. Defer tests specifically asserting open-row coercion and the former effect quantifier's printed output. |
| `assert`, `println`, `assertEq`, `showLocal`, `localYear`, `localDay`, `localMonth`, `localHours` | Translate to `[wild]` for logging, printing, exit or use of local time. `localMinutes`, `localSeconds` and `localMilliseconds` use UTC-independent projections and are pure. |
| `the`, `fromJust`, `assoc` | Translate: preserve failure via `error` and apply its native permission decision. `the`'s `all` predicate uses the same context. |
| `elem`, `selectElem`, `!!`, `odd`, `even`, `intRange`, `and`, `or`, `swap`, `unzip`, `zip`, `replicate`, `substAt`, `reverse`, `concat`, `join`, `init`, `curtail`, `last`, `intercalate`, `unlines`, `unwords`, `empty`, `product`, `sum`, `sumF`, `avg`, `avgF`, `minimum`, `maximum`, `max_list`, `maxF_list`, `min_list`, `minF_list`, `memassoc`, `lookup`, `assocDefault`, `removeAssoc`, `assocAll`, `dedup` (including local `elem` and `aux`), `lookupG`, `elemIndex` | Translate: pure list, tuple and numeric functions. Keep partial-pattern failures and type bounds; remove the old requirement for `wild` from recursion, ranges and deterministic primitives. Bind desugared ranges to the standard pure `intRange`. |
| `ignore`, `id`, `first`–`tenth`, `abs`, `isInt`, `isFloat`, `isLower`, `isUpper`, `isAlpha`, `isDigit`, `isAlnum`, `isXDigit`, `isBlank`, `toUpper`, `toLower`, `utcYear`, `utcDay`, `utcMonth`, `utcHours`, `utcMinutes`, `utcSeconds`, `utcMilliseconds` | Translate: retain pure functions and any existing value or data-row polymorphism. |
| `unsafe sig` declarations | Change expectation: use checked signatures for `concatMap`, `map`, `sortByBase`, `sum`, `sumF`, `max_list`, `maxF_list`, `min_list`, `minF_list`, `dedup`'s `elem` and `aux`, and `lookupG`. The old bypass was for recursion's implicit `wild`. |

The [FreezeML prelude](../../tests/freezeml_prelude.links) has 18
explicit signatures and one type alias. Update it with
[`tests/freezeml.config`](../../tests/freezeml.config)'s existing test
coverage.

| Definitions | Classification and migration |
| --- | --- |
| `head`, `tail`, `single`, `id`, `ids`, `inc` | Translate: pure functions, including a list of frozen polymorphic functions in `ids`. Keep value quantifiers and `List` element types. |
| `ST`, `runST`, `argST` | Translate: the absolute empty context belongs on the state thunk. Retain the higher-rank `forall s` argument. |
| `pair`, `pair'`, `choose`, `poly`, `auto`, `auto'`, `map`, `revapp`, `app`, `first` | Translate: use ambient arrows for callbacks used where they were supplied, or an explicit pure type on a stored or frozen callback that needs it. Preserve the order of the value quantifiers in `pair` and `pair'`, the nested `forall` in `poly` and `auto`, and existing linearity bounds. `choose`, `auto'`, `map`, `revapp` and `app` have separate old arrows for application stages which run no callback; their test calls can share one context. |
| Explicit effect instantiation and print expectations | Change expectation: remove effect arguments and retain remaining value, data-row and presence arguments and quantifier order. Preserve rejections of higher-rank use with insufficient type information. |

The installed modules under [lib/stdlib](../../lib/stdlib) are
`BinaryTree` and `Comparators). Translate `BinaryTree(a)`,
`empty`, `invert`, `traverse_preorder`, `traverse_inorder`,
`traverse_postorder`, `add`, `leftmost_child` and `remove`. Use
`List a` for traversals and one ambient context for each comparator
and the functions that call it. `Comparators.intComparator` is pure.
Keep the traversal and removal results in `tests/binaryTrees.tests`
and its five files under `tests/stdlibtests/binaryTree/`.

## Installed examples

At the baseline, all 35 `.links` files under [examples](../../examples) had entries in
[`tests/typecheck_examples.tests`](../../tests/typecheck_examples.tests).
The table uses paths relative to `examples/`; each row includes its
typecheck registration. Any retired example needs matching changes
to the installation list in `examples/dune` or
`examples/handlers/dune` and to the registration checked by
`tests/validate_typecheck_testfile.testscript`.

| Files | Classification and migration |
| --- | --- |
| `church.links` | Translate: `Nat`, `zero`, `succ`, `add`, `two`, `four`, `natToInt`; retain the higher-rank pure numerals and callbacks. |
| `extensible-case.links`, `linearList.links` | Translate: preserve open variant rows and callback use in `add_A`, `add_B`, `add_C`, `defaultCase`, `nocases`, `sub_A`; preserve `LinList`, `linMap` and `inc`'s linear closure with its pure requirement. |
| `factorial.links`, `mandelcolor.links`, `paginate.links` | Translate: pure ranges, comprehensions, recursion, sorting and list operations in `lookupFactorials`, `mandelmatrix`, `mandelregion` and `find`. |
| `sierpinski_bits.links`, `TicTacToe-Console.links` | Translate: pure `zipbits` callback and `Bits` list type; `sierpinski` requires `wild`. Translate `Player`, `maybeToString`, `listToString` and list signatures; `printState`, `addMove`, `playGame` and its printing branches require `wild`. |
| `handlers/identity.links`, `handlers/choose.links`, `handlers/coin_composition.links` | Translate `force` as a return-only handler. Declare `Choose` and `Fail`; give `positive`, `enumerate`, `allChoices` and `failure` relative callbacks and `toss`, `drunkToss` known operation requirements. Keep both composition orders in `run`, which prints. |
| `handlers/coins.links` | Translate local `Comp` and `CF` uses, `choice`, `choose`, `fail`, `allResults`, `drunkToss`, `drunkTosses`, `rand`, `randomResult`, `persevere`, `maybeResult`, `handleRandom`. Use complete Choice, Failure and Rand interfaces in each handler. `randomResult` handles Choice and invokes Rand from its enclosing clause; `handleRandom` calls native `random`. |
| `handlers/count.links`, `handlers/toggle.links`, `handlers/deep_state.links`, `handlers/shallow_state.links` | Translate `get`, `put`, `toggle`, `count`, `runState`, `evalState`, `logVal`, `logPrinter`, `logAccumulator` and `compify`. Group Get and Put in one State interface, and Log separately. Use a new handler for calls through shallow resumptions and a shared invocation context for `compify`. Preserve state and log results in `unitTest`. |
| `handlers/light_switch.links` | Translate `LState`, `get`, `put`, `toggle`, `flickering`, `flickering_st`, `evalState`, `evalState0`, `logState`. Give the inner `logState` an explicit Get clause forwarding to the outer State handler; pass the current history to its resumption. Keep Put forwarding and the `unitTest` comparison. |
| `handlers/transaction.links` | Translate Queue/Bank data and State/Abort requirements in `runState`, `beginTransaction`, `transfer`, `abort` and `example`. `beginTransaction` must explicitly forward Get and pass the current transaction state when it resumes. The concrete demo fixes `Co` and Fork's payload at State, Cooperative and `wild`. The scheduler passes its queue of ambient resumptions through handler result functions in one shared context. Defer the generic fork API wherever the payload must retain a varying outer context under a separately chosen fork/handler context. |
| `handlers/concurrency.links` | Translate the concrete `test` and all three scheduler combinations with a fixed absolute `Co` payload for Fork and an explicit queue of ambient resumptions. The demo and random selection require `wild`. The separate `zipQueue` handler retains Enqueue and Dequeue with an absolute interface argument. Defer generic payloads that must keep an independently chosen queue/process context after the current scheduler removes its own interface. The current file declares the demo and leaves the final invocation commented out. |
| `handlers/coop.links`, `handlers/monadic_reflection.links` | Translate `Co`, `Res`, `ResList`, `fork`, `yield`, `stop`, `test`, `coop`, `run` with cooperative resumptions in the same enclosing context. Translate `State`, `return`, `run`, `bind`, `>>=`, `get`, `put`, `reify`, `reflect`, `getR`, `putR`: use an absolute pure state function for Reflect's payload and an `Abs` operation result quantifier. Check the native permission of the printing `example` and `runExample`. |
| `handlers/aop.links`, `handlers/aop2.links` | Translate `runState`, `evalState`, `runStringWriter`, `printer`, `get`, `put`, `tell`, `Env`, `bevalStep`, `beval`, `suspend`, `force`, `logger`, `dump` and `test0`–`test3`. For the concrete evaluator use a fixed absolute recursive Suspend payload for the known State/Writer/Suspend interfaces and native calls. Keep reissuing Suspend in the enclosing clause where the code does so. Defer the syntax of `SComp(e,a)` as an alias taking an effect argument. Verify that fixing the operation payload still permits all four advice combinations. |
| `handlers/exceptions.links` | Translate `input`, `sumUp`, `fail`, `parseInt`, `prompt`, `catchFail`, `printResult`, `catchResume`, `sumUpSilently`, `example1`, `example2`, `unitTest`. Input and Fail need separate interfaces; `prompt` handles Input and calls Fail in the enclosing context. Compose the resulting relative callbacks with their known types; preserve the printing and silent cases. |
| `handlers/fringe.links` | Translate `Tree`, `yield`, `walkTree`, `Continuation`, `Status`, `step` and `sameFringe`. `walkTree` yields absolute leaves. Store deep resumptions in `Status` in the enclosing context of `step` and run both in the same context. `sameFringe_aux` has a pure comparison and shares the context of those resumptions; its old `gen2` use and `step`'s second row do not require two independent resumption contexts for this program. Keep `unitTest` and the printing `runExamples`. |
| `handlers/lambda.links` | Defer the [lambda evaluator](deferred/independent-effects/lambda.links). Its shallow Lam resumption must keep the caller's Lam context when the evaluator sends a closure through Var. Var requires an absolute payload and result, so an absolute annotation on the replacement closure cannot preserve the resumption's relative requirement. Remove the installed example and its typecheck registration together. |
| `handlers/nim.links` | Translate `Player`, `GameTree`, `GameState`, `move`, `aliceTurn`, `bobTurn`, `game`, `ns`, `ps`, `naive`, `perfect`, `validMoves`, `bfs`, `reifyMove`, `pvb`, `gametree`. Translate Move/Cheat/Rand/State requirements in `bobStrat`, `check`, `checkedGame`, `aliceCheats`, `aliceCheats2`, `cheatReport`, `cheatLose`, `cpReport`, `cpLose`, `rand`, `ms`, `mixed`, `randomFloat`, `notReallyRandom`, `strategy`, `get`, `put`, `state`, `scorerecorder`, `boardPrinter`, `repeatGame`–`repeatGame3` and their helpers. Preserve explicit Move forwarding and the return-only handlers in `scorerecorder` and `boardPrinter`. Replace optional Move presence in `strategy` by an ambient dependency, with an added Move instance for its input computation. |
| `handlers/number_games.links`, `handlers/u2_puzzle.links` | Translate `Answer`, `readInt`, `guess`, `input`, `mySecret`, `logger`; preserve Guess forwarding and native printing. Translate `U2`, `Side`, `Ordering`, `showMembers`, `choose`, `fail`, `selectParty`, `solve` and their helpers with independent Choose/Fail interfaces and absolute choice payloads. |
| `handlers/pi.links` | Translate `yield`, `await`, `abort`, `Point`, `randomPoints`, `take`, `computePi`, `Resumption`, `Step`, `step`, `exchange`, `Consumer`, `Producer`, `copipe`, `pipe`, `catch` and the estimators. Keep Await and Yield separate, store deep resumptions in the common enclosing context, and restore the appropriate interface before calling a shallow resumption. Preserve `wild` for random points and display. |
| `handlers/pipes.links` | Translate `await`, `yield`, `forever`, `blackhole`, `take1`, `produceFrom`, `skip1`, `printer`, `forward`, `collect`, `Producer`/`Consumer`, `Pipe`/`Copipe`, `Prod`/`Cons`, both `pipe`/`copipe` pairs under `Deep` and `Shallow`, `>+>`, `expoPipe1` and `expoPipe`. Each pair relates an Await extension and a Yield extension of the same enclosing context. Use separate complete interfaces, check higher-rank annotations where the deep encoding takes a pair of combinators, and retain both direct and encoded variants. Replace effect-presence quantifiers for known Await/Yield instances with relative requirements. Preserve the aggregate's nested pipeline output from `nested_example`. |
| `handlers/sat.links` | Translate `Expr`, `Polarity`, `run`, `fail`, `maybe`, `leftBiased`, `choose`, `freeVariable`, `satisfiable`, `Parser`, `ExprParser`, `satisfies`, `char`, `peek`, `succeed`, `many`, `many1`, `while`, `parens`, `parse`, `parseTextExpression` and the parsing and solver helpers. `Satisfies` takes a pure absolute predicate; call it directly in place of `gen1`. Keep Fail separate so `parse` can invoke it in clauses and `maybe` can handle it. Replace `gen0` with a thunk carrying the resulting fixed or relative requirement, including `wild` on the printing path. Keep both `unitTest` assertions. |
| `handlers/shiftreset.links` | Translate `shift`, `reset`, `comp`, `yield` and `example` using a fixed absolute payload for the supplied callback and its continuation argument, with interface parameters for the answer and operation result types as needed. Verify both the integer continuation in `comp` and the list continuation in `example`. Defer the old signature's effect presence and effect-tail syntax. The example uses a handler operation, so the `escape` deferral does not apply. |
| `handlers/sudoku.links` | Translate `Status`, `Sudoku`, `emptySudoku`, `dup`, `testSudoku`, `>>=`, `return`, `checkSudoku`; retain nested lists and an ambient Maybe callback. |
| `handlers/tests.links` | Translate `pairToString`, `listToString`, `assert`, `stateExamplesToString` and `runTests`; use a suitable absolute type for the global printer value it shares. Its nine registered assertions are `shallow_state`, `deep_state`, `deep_pipes`, `exceptions`, `fringe`, `light_switch`, `sat`, `pi` and `delim`. Preserve the imports, assertions and `--path=examples/handlers` in both `handlers.tests` (Examples) and `typecheck_examples.tests`. Any deferred assertion needs a named dependency here and a matching change to the aggregate's imports and call list. |

## Effect and handler regressions

Suite names below refer to files under [tests](../../tests). A range
of numbered cases includes each occurrence of the named heading. Keep
the configuration file and per-case arguments which still apply.

| Fixture | Classification and migration |
| --- | --- |
| `handlers.tests`: Identity handler (1–2), Listify handler (1–4), Handler rejected when handlers are disabled, Binary choice handling (1–2), Exception handling (1–6) | Translate: retain identity, implicit and explicit returns, list results, disabled-handler rejection, multi-shot choice, and rejection when a resumption is given the wrong result of Fail. |
| `handlers.tests`: Top level operation invocation; Operation invocation sugar (1–6) | Change expectation: require a declared Foo and an available instance. Use nullary declarations for `do Foo` and `do Foo()`; use a one-unit-argument declaration for `do Foo(())`. Supply the expected modal type in accepted cases. Keep separate checks for an unknown operation and a declared operation outside its context. |
| `handlers.tests`: Deep continuation escape (1–2) | Translate: declare the nullary operation Escape. Retain `Just(k)` and the use of the stored deep resumption. These cases exercise handlers. |
| `handlers.tests`: Type-and-effect signature for deep handler (1–3), shallow handler (1–3); Type inference for deep handler; Soundness | Translate the callback requirements and resumption types. All six allChoices cases install Choice and return the appropriate list or thunk. Keep the check that a handler for A leaves B to the enclosing context. Preserve the Soundness rejection with a declared Map and an explicit callback type. |
| `handlers.tests`: Deep state handling (1–3), Shallow state handling (1–2), Shadowing handler parameter (1–3) | Translate: one State interface with a shared absolute argument for Get and Put. Preserve argument order, local names, shallow handler reinstatement and the effect of shadowing. |
| `handlers.tests`: Operation parameter pattern-matching (1–9), An unmatched operation pattern raises a match error, Pattern-matching on continuation parameter (1–3), Value parameter pattern-matching (1–6), Pattern-matching on handler parameter (1–8; two cases numbered 2) | Translate operation and resumption types and preserve all pattern successes and failures. Check that a failed operation pattern raises its match error even when an enclosing handler could handle it. |
| `handlers.tests`: Deep Handler composition; Deep operation clause can forward its operation to the enclosing handler; Deep return clause runs in the enclosing handler's context; Resuming a forwarded operation runs the inner return clause; Combining choice and state handlers | Translate: keep the distinct forwarding and clause-context cases, and migrate `handlers/choose_and_state.links` with declared Choice and State, signatures for `incr`, `choice`, `enumerate` and `evalState`, and the same two handler orders. |
| `handlers.tests`: Type annotation on deep continuation parameter; Type annotation on shallow continuation parameter; Shallow addition with a single recursive handler; Shallow addition with two mutual recursive handlers; Shallow handler composition; A shallow resumption runs under a new handler and skips the original return clause | Translate: the deep resumption uses the enclosing context and the shallow resumption retains the handled extension. Declare Op, One and the other operations in the relevant cases. Keep the return and resumption checks. |
| `handlers.tests`: Type ascription, parameterised handlers (1–2); Parameterised handler with multiple parameters (1–2); Handler state initialisers run left to right in the enclosing context | Translate: keep typed state ascriptions and multi-state argument order. Require absolute initial state and preserve left-to-right initialisation before the handler is installed. |
| `handlers.tests`: Instantiate.ArityMismatch #132; Operation polymorphism (1–3); Generalise (1–2); Recursive nesting of deep handlers | Translate the handler and callback shapes. Declare Fail and Switch with operation quantifiers over absolute types; share only the interface parameters. Replace `gen0` with a pure annotation and check the resulting thunk. Defer the original row-generalisation print expectation. |
| `handlers.tests`: Effect type sugar (1), Effect type sugar for a nullary operation with a wild arrow, Effect type sugar (3); Operation annotation (1–3) | Change expectation: replace the operation fields with interface declarations. Test the zero-argument operation declaration, native permission, agreement between a clause annotation and its declaration, and an absolute function returned by an operation. |
| `handlers.tests`: Implicit return case (1–2), Omission of resumption for nullary operations (1–3), Handled operation may be absent from the output row, Unhandled operation cannot be absent from the output row | Translate: compare return-only and handling contexts. The checked body can call Ask only when its requirement is available. Retain ignored resumptions. |
| `handlers.tests`: Applying a linear function to an operation result, Repeated resumption of a computation using a linear local, Deep handler operation clause can use a linear argument, Deep handler operation clause cannot use a linear local, Shallow handler operation clause can use a linear local, Shallow handler cannot use a linear local twice, Shallow handler return clause can use a linear local, Deep handler return clause cannot use a linear local, Deep handler return clause can use its linear result once, Deep handler return clause cannot use its linear result twice | Translate: preserve accepted and rejected uses of captured linear values and handler return binders. Preserve resumption replay of the computation using the linear local. |
| `handlers.tests`: Examples; `repl_handlers.testscript` | Translate the aggregate described above. In the REPL declare Ask and add the signature for `ask` before its definition, then keep its call under a handler in a later sentence. |
| `effect_annotations.tests`: Bare arrows have distinct open effect rows; Bare wild arrows have distinct open effect rows; A function cannot use an unrelated open effect row | Change expectation: bare arrows share their ambient context and the same-context callback is accepted. The old wild arrow is rejected as syntax. Compare permitted and rejected calls with a fixed native requirement. |
| `effect_annotations.tests`: A handler shares an explicit effect tail with its input computation; Anonymous effect tails are independent in a handler signature; An operation omitted from a row is unavailable; An absent operation cannot be invoked | Translate the shared handler requirement to a relative type. Change the old anonymous-tail mismatch to a missing or incompatible modality. Retain the unavailable-operation rejections. |
| `effect_annotations.tests`: Named effect presences can be shared across rows; Flexible effect tail and presence variables; The printer keeps an anonymous tail's effect kind | Defer the old effect-row presence variables, inference and effect-kind printing. Retain the handler's shared-context behaviour with an ambient context and explicit interfaces. |
| `effect_annotations.tests`: Braced record presence and absence; Braced effect presence and absence; Polymorphic nullary operation shorthand | Translate the braced data-row case unchanged apart from the surrounding function type. Change the effect-field cases to interface declarations and check the polymorphic operation's own `Abs` quantifier. |
| `effect_annotations.tests`: Linear arrows can have open or closed wild rows; Closed empty effects do not admit wild; Dot syntax in effect rows is rejected; Removed effect sugar setting is unknown; Removed effect sugar policy setting is unknown | Translate the native permission checks, including a linear function. Change the invalid syntax case to check that old effect arrows are rejected. Keep both unknown-setting checks. |
| `effectname.tests` and `effectname/*.links` (12 files) | Translate `simple-decl`, `zero`, `one`, `two`, `typenames`, `nested-decl`, `handler` and `underscore` into declarations, type arguments, scoped contexts and handler tests as applicable. Change `two-nested` to check that repeated instances stay distinct, `effect-same-name` to reject duplicate operation names, `recursive` to check a permitted self-reference with an absolute payload and reject its ambient counterpart, and `mutual` to check declaration lookup. Defer tests of effect-alias expansion and effect arguments. The active `underscore` fixture checks an absolute callback against a relative interface requirement. |
| `native.tests`: Handler patterns still accept adjacent angle brackets; Former session exception operation can be resumed | Translate with declared Ask and SessionFail. Retain the angle-bracket spelling and result. |
| `native.tests`: Foreign function declaration and block; Mailbox effect shorthand; Hear is an ordinary labelled effect field; Linear operation type/pattern arrows and linear effect row subkind | Preserve unsupported native-language checks. Use a current type in the foreign cases, an interface declaration to demonstrate legal operation labels, and current interface/handler forms around the disallowed arrow. The old effect field and subkind forms become syntax rejections. |

## Polymorphism, data and compiler regressions

| Fixture | Classification and migration |
| --- | --- |
| `annotations.tests` | Translate More-specific type annotation with typevars, inner annotations, inferred kinds, recursive variant patterns and pure recursion. Use the approved signatures in the former `unsafe sig` cases; retain wrong value types, the rejected polymorphic shape, and the rejection of a native call under `[]`. Change Kind mismatch [1] to an equivalent data kind error or reject the retired syntax explicitly. |
| `functions.tests` | Translate Infers effect variables as a same-context call and Type alias with an operation parameter using two Reader instances with distinct value arguments. Preserve closure scope and hoisting in `innerfun1`–`innerfun3`, `nested-functions-polymorphic`, `closure-conv-type-abstr-only` and `escaped-quantifier`; the last concerns quantifier scope. Translate linear arrows and linear capture/use cases. |
| `mutual.tests` and `mutual/*.links` | Translate ordinary and mutually recursive functions, polymorphic recursion and linearity. Rename the user-defined `List` in `list.links`, `listWrong.links` and `listMap.links`, keeping the recursive variant type, the positive and negative results, and the map callback test. Add a rejection using the reserved name. |
| `polymorphism.tests` | Translate let/value restrictions, polymorphic and mutual recursion, row recursion, the curried `zipwith`, annotated higher-rank callback, freeze/application and signature scope cases. Move Read to a parameterised interface in Polymorphic result of an operation in a function. Translate Flexible quantifier elimination to known relative callbacks or preserve its separate quantifier test with a data kind. Retain Church numeral, recursive type and type abstraction tests. Change examples whose acceptance previously depended on an inferred fresh effect row, and defer the assertions solely about effect quantifier count, spelling, presence or shadowing (including the row-specific ambiguity in Type abstraction: Ambigous type (2)). Preserve equivalent value/data-row kind tests, including rejection when a used value variable is missing from an explicit quantifier list. |
| `freezeml.tests` and `freezeml/{a9,c8,e1,e2,e3,e4}.links` | Translate Polymorphic Instantiation, Inference of Polymorphic Arguments, Functions on Polymorphic Lists, Application functions, η-expansion and FreezeML programs with the migrated FreezeML prelude. Preserve higher-rank accept/reject, no inference of new `forall`, the value restriction, `Mono` and mutual recursion cases. Keep and reprint the explicit data presence and row applications and the wrong-kind rejection. Recheck any case expecting a modal type to be inferred when the expected type must now supply it. |
| `desugar_datatypes.tests` and `desugar_datatypes/{nestedQuantifiers1,nestedQuantifiers2,nestedTypename,shadowKinds}.links` | Translate data alias scope, declared kinds, duplicate variables, nested quantifiers and non-effect kind mismatches. Change A quantified signature cannot use a fresh implicit effect row and Implicit type variables are detected: bare arrows no longer introduce an anonymous effect variable. Rebuild Comp arity and kind checks as data alias or interface argument checks. Defer the syntax-specific effect argument, alias-tail and effect-kind inference tests; preserve applicable scope and kind mismatches using data types. |
| `parser.tests` | Translate the recursive record and variant rows, `Mono`, and Recursive type variable in codomain. The payload of the Op variant can have an ambient function type. Change the recursive effect signature tests to declared interfaces with absolute recursive payloads. Defer Recursive row variable in row type argument, and the old effect-tail syntax assertions in Recursive row variable in effect signature [1–2]. Preserve the data-row recursion in Recursive row variable in variant [1]. |
| `presence_type_arg.tests`, `presence_type_arg_typename.links` | Translate all seven data-presence applications, including flexible, anonymous, absent and explicit present payloads. Change No implicit wild present with type unit [1–3] to the rule that native permission is not an interface operation and cannot be annotated with a payload. |
| `type_print.tests` | Translate Shared effect in a higher-order function, Independent effect in a curried arrow, Shared effect across a tuple and the thunk-alias application/return cases: a callback used in the final stage and that stage can share one ambient context. Change the expected formatting to modal value types. Defer assertions about old effect-tail sharing, omission and independence in Anonymous effect tails after operation fields, Single-use effect tails, Shared effect tail in curried arrows, Distinct effect tails across a tuple and the effect-tail part of Type aliases with a shared effect tail. |
| `roundtrippable_types.tests` and `roundtrippable_types.testscript` | Translate Base row types, Onetuple with unit, Alias record functional update, Quantified presence in an alias argument, and Quantified value type that admits linear values. Translate the wild alias and nested wild row cases to printing and reparsing an absolute `[wild]`. For Recursive effect (and the script's Recursive effect row), give the operation F an absolute thunk payload referring back to its declared interface. Defer Quantified effect tail and effect presence as an effect-variable printer test. Preserve the script's print–parse–print equality check for each replacement. |
| `typed_ir.tests` and `typed_ir/` | Translate the #693 constant, identity, composition and application cases, T368, T574, T620, T691a, T691b, T692, T694, T697a, T697b, T698, T876 and T877. Keep callback and data quantifier coverage and checked recursive signatures. Change the native/recursion expectations of Wild effect compatibility #1 and #2 to test a pure callback or a genuine native requirement as appropriate. Retain both Apply a callback cases (including the linear arrow), the direct pattern matching and `isInt` cases, type freshening and value restriction. The four escape entries are listed below. |
| `recheck_frontend_transformations.tests` | Translate default-prelude rechecking and T865 and T882, keeping their type freshening and mutual-recursion checks and existing configuration. |
| `collections.tests`, `operators.tests`, `library.tests`, `functions.tests`, `polymorphism.tests`, `bindings.tests`, `conditionals.tests`, `cliArgs.tests`, `datetime.tests`, `strings.tests`, `records.tests`, `patterns.tests`, `variants.tests`, `switch_functions.tests`, `modules.tests`, `regex.tests` | Translate old list/variant type syntax, printed types and diagnostics wherever present. Preserve list and variant terms, data rows, comprehensions, local and imported callbacks, standard helper behaviour and range results. Include `fixity.links`, `records_oop.links`, `roundtrip/record_update.links`, `wikiparser.links`, `modules/mutualtys.links`, `modules/qualified_type_payload.links`, `modules/qualified_signature_importer.links` and the constructor/module scoping fixtures when updating their surrounding annotations. |
| `crypt.tests`, `datetime.tests`, `cliArgs.tests`, `library.tests` and `check-install.sh` | Translate native entry point regressions with top-level `wild`; keep the crypt and date results, CLI argument contents and the exit codes and output of Test sysexit [0–2]. Check that an empty context rejects actual native effects and accepts calls to pure primitives. Update the installed `map` output from `[42] : [Int]` to `[42] : List Int` and keep the import test from outside the checkout. |
| `unit/ir/test_cases/effects.ml` and shared IR builders | Change Toplevel wild to accept calling a pure function under the top-level permission. Translate instantiation1–3, fun_binding_no_effects and let_binding_effects to the applicable fixed context, relative context, plain function binding and actual call checks. Defer instantiation4's arbitrary quantified effect-row argument. Retain data-row instantiation tests and distinguish native effect permission from `ApplyPure`. Translate function, binding and closure fixtures that use the shared effect-arrow builders. |

## Deferred `escape` fixtures

There are 22 registered cases using the `escape` term and no such
uses in the installed examples. Milestone 2.2 moved the original cases
to [the archive](deferred/escape/) and added diagnostic tests with and
without handlers enabled.

| Fixture | Cases and reason |
| --- | --- |
| [continuations.tests](deferred/escape/continuations.tests) | All 18: Escape expressions; Nested escapes; Invoking escapes; Continuation typing [1–5]; Escape through a higher-order function; Escape through a higher-order function rejects the wrong result type; Escape from a handler clause; Escape body [1–6]; Escape with handlers disabled. All exercise capturing or using an `escape` continuation, including the separate handler-disabled runtime. |
| [typed_ir.tests](deferred/escape/typed_ir.tests) | Wild effect compatibility with escape from a closure (#873, 1), backed by [T873.links](deferred/escape/T873.links); Wild effect compatibility #4 (#873, 2); Wild effect compatibility #5 (#873, 3); Call/cc. Each depends on `escape` to obtain a continuation. |

The SmallLinks examples and active regressions contain no term-mask
programs. A future reference test relying on executing an ambient
callback through a handler it must bypass needs the postponed term
mask. Keep mask-type and value-transport tests in scope.

## Archived effect-row fixtures

- [Effect annotations](deferred/effect-rows/effect_annotations.tests)
  recorded shared, flexible and anonymous effect-row variables. The
  active suite checks relative callbacks and preserves data presence
  annotations.
- [Generalise (1–2)](deferred/effect-rows/handlers.tests) checked
  row-generalising coercions and the printed effect-row argument of
  `Comp`. The active suite checks the absolute thunk type and the
  annotated resumption.
- [Effect alias declarations](deferred/effect-rows/effectname-declarations.links)
  exercised effect-alias expansion with open and closed effect
  arguments. The active suite checks declared interfaces, alias
  signatures and scoped instances.
- [Underscore in an effect alias application](deferred/effect-rows/effectname-underscore.links)
  used an anonymous effect-row argument. The active fixture checks
  that an absolute callback with a fixed interface satisfies a
  handler's relative requirement.
- [Datatype desugaring](deferred/effect-rows/desugar_datatypes.tests)
  checked a required effect argument and a restriction on anonymous
  tails of effect aliases. The active suite checks data-row arguments
  and kind errors.
- [Parser](deferred/effect-rows/parser.tests) used recursive effect rows
  in signatures. The active cases check an interface that refers to
  itself through an absolute operation payload and rejects the
  ambient payload.
- [Type printing](deferred/effect-rows/type_print.tests) checked
  anonymous, shared and distinct effect-row tails. The active cases
  check printing ambient and absolute arrows.

## Modal regressions in the native runner

[Effect annotations](../../tests/effect_annotations.tests),
[effect interfaces](../../tests/effectname.tests) and
[handlers](../../tests/handlers.tests) run the syntax, typing and
behaviour checks from [the modal design](SPEC.md#accepted-and-rejected-programs).
They cover inferred and annotated callbacks, nested instances, absolute
payloads and results, relative resumptions, mask transport, complete
interfaces and the native permission. The higher-rank checks use a
frozen function with a declared value quantifier. The REPL handler
fixture uses the operation declaration in a later sentence.
