# Modal effect examples

The [example README](../../examples/met/README.md) gives run commands.
[Example notes](example-issues.md) record defects, unsupported
features and typing differences.

## Status

All 60 registered examples passed their runtime or expected rejection
checks in default and strict configurations. The standalone
[Church callback](../../examples/met/fresco-types/church-pair-result.links)
keeps its unconstrained accumulator type. The
[Fresco evaluator issue](example-issues.md#the-fresco-evaluator-loads-eager-definitions-in-reverse-order)
remains open in the reference interpreter.
The [thesis inventory](#thesis-tutorial) records the deferred generic
`Coop e` interface and the two adaptations for term masks. The
[Fresco inventory](#fresco-effect-and-data-examples) records the two
excluded rejection cases.

## Sources

- Wenhao Tang's thesis at `eabef130ffb744840fe8a52e0cbb4045fe2cc397`.
  The tutorial is `chapters/overview.tex`.
- The Fresco artefact at `333738dbe9da1dcd094a6b2c2c9dbb9eec701ea4`.
  The source material is the README program, `tests/pass`, `tests/fail`
  and the appendix tests in `tests/fresco/pass` and `tests/fresco/fail`.

## Example source coverage

The inventory covers 42 thesis listings and 83 Fresco programs, test
files and README examples. Shared examples and related typing cases
use the same SmallLinks file.

### Thesis tutorial

The source is `chapters/overview.tex` in `phd-thesis` at
`eabef130ffb744840fe8a52e0cbb4045fe2cc397`. The chapter has 42 listings
and includes no separate source files.

| Source lines | Example | Coverage |
| --- | --- | --- |
| 62–65, 69–72, 76–79, 84–88, 92–96, 116–125 | [pure.links](../../examples/met/thesis/pure.links) | `pi`, `inc`, `pinc`, `map` and curried `iter`. Both placements of `forall` around the outer `[]` are checked for `map` and `iter`. Returns `((), [4, 2, 5, 2, 6, 10], 42, 43)`. |
| 180–185 | [print_list.links](../../examples/met/thesis/print_list.links), [handlers.links](../../examples/met/thesis/handlers.links) | `IO`, `Gen`, `State` and `ND`. The `PolymorphicResult.ND` interface gives `Fail` the absolute polymorphic result `[] (forall a. a)`. The last result list is `[42]` after dropping the failing branch. |
| 231–240, 262–265 | [handlers.links](../../examples/met/thesis/handlers.links) | Bare arrows for the three local increment functions share the context containing `Gen(Int)`, `State(Int)` and `ND`. The local run returns `(6, 64, [4, 2, 5, 2, 6, 10])`, giving the final state, number of possible lists and yielded values. |
| 276–278 | [iter_pure_result.links](../../examples/met/thesis/rejected/iter_pure_result.links) | Rejects access to `f` under the empty context asserted by the returned function's `[]`. |
| 288–291 | [print_list_without_io.links](../../examples/met/thesis/rejected/print_list_without_io.links) | Rejects `do Print` because `IO` is absent from the current context. |
| 316–325, 385–390, 395–401, 406–412, 417–426 | [handlers.links](../../examples/met/thesis/handlers.links) | Increment functions with absolute contexts and three handlers with relative callbacks. `asList` returns `[4, 2, 5, 2, 6, 10]`. `all` produces 64 lists, from `[4, 2, 5, 2, 6, 10]` to `[3, 1, 4, 1, 5, 9]`. `state` returns `6`. |
| 349–352 | [print_list.links](../../examples/met/thesis/print_list.links) | `printlist` uses a callback and `Print` in `[IO]`. A mock `Read` supplies the heading, and the handler collects `["digit 3", "digit 1", "digit 4"]`. |
| 458–460 | [handlers.links](../../examples/met/thesis/handlers.links), [absolute_generator_callback.links](../../examples/met/thesis/rejected/absolute_generator_callback.links) | The absolute `asListAbsolute` callback yields `[42]`. The callback that also calls `Get` is rejected because its `[Gen(a)]` context excludes `State`. |
| 514–517, 526–529 | [handlers.links](../../examples/met/thesis/handlers.links) | The inner `state` handler forwards `Yield` to `asList`. Returns prefix sums `[3, 4, 8, 9, 14, 23]`. |
| 546–550, 555–558 | [handlers.links](../../examples/met/thesis/handlers.links) | The inner `state` handler forwards `Choose` to `all`. Returns 64 sums, starting with `[23, 14, 18]` and ending with `0`. |
| 588–594, 625–627 | [find_unannotated_callback.links](../../examples/met/thesis/rejected/find_unannotated_callback.links), [find.links](../../examples/met/thesis/find.links) | Rejects calling the bare predicate under a new `Gen` handler. The relative predicate `<Gen(a)> (a -> Bool)` supports that call. The successful search, failed search and predicate that yields return `(Just(6), Nothing, Just(12))`. |
| 649–655 | [find_mask_paper.links](../../examples/met/fresco-effects/find_mask_paper.links) | The term `mask<Gen>(p x)` needs term-level masks. The shared port handles `Test` and the local `Yield` together. Its `Test` clause calls the predicate in the enclosing context, so its yields reach the caller. The `observed` result is `(Just(2), [1, 2])`. |
| 687–690 | [yield_state.links](../../examples/met/thesis/yield_state.links) | The original `yieldState` API needs a term mask to call `<Gen \|>` under a caller-installed `Gen`. The runnable version handles a new `RunCallback` operation together with the inner `Gen(Int)`. The callback updates the current `State` and yields to the outer `Gen(String)`. The resumption yields the updated state to the inner handler. Returns `([42], ["callback"])`. |
| 721–723 | [processes.links](../../examples/met/thesis/processes.links) | A recursive variant `TutorialList` represents `Nil` and `Cons`. Summing the example list returns `42`. |
| 732–741, 753–756 | [processes.links](../../examples/met/thesis/processes.links) | A `Proc` constructor stores a callback with an ambient arrow. `push` appends a process while `next` passes the remaining queue. Running two copies of `[State(Int)] Proc` increments state from `40` to `42`. |
| 762–764, 774–780 | [processes.links](../../examples/met/thesis/processes.links) | First-order `UFork` and `Suspend` with a cooperative queue. Forwards `Note` across the scheduler and records `["start", "child", "parent", "child resumed", "parent resumed"]`. |
| 813–815, 826–828 | [handler_results.links](../../examples/met/thesis/handler_results.links), [state_result_escape.links](../../examples/met/thesis/rejected/state_result_escape.links) | `state` requires `a::Abs`. The ambient closure `() -> ()` with `Get` and `Put` in its body cannot instantiate that argument. |
| 888–894, 905–907 | [handler_results.links](../../examples/met/thesis/handler_results.links) | `state'` records `<State(s)>` in its result type. The returned closure runs in a second `State(Int)` handler and increases its state from `10` to `52`. |
| 929–932, 948–950 | [state_payload_escape.links](../../examples/met/thesis/rejected/state_payload_escape.links), [handlers.links](../../examples/met/thesis/handlers.links) | `State(s::Abs)` enforces an absolute payload for `Get` and `Put`. Rejects storing an ambient closure which would call `Yield` after leaving its `Gen` handler. |
| 993–995 | [higher_order_coop.links](../../examples/met/thesis/higher_order_coop.links) | `Fork` takes a child of type `[Coop] (() -> ())`. Parent, child and grandchild suspend once each, returning `3`. |
| 1006–1008 | Deferred | `Coop e` needs an effect variable for the independently chosen context of a child. A bare arrow shares the current context but gives the operation a non-absolute payload. A fixed absolute annotation assumes one set of additional effects. |
| 1044–1046, 1051–1053 | [handler_results.links](../../examples/met/thesis/handler_results.links) | `state` returns `List (forall a. [] (a -> a -> a))` without explicit type instantiation. Calling the returned functions at `Int`, `Bool` and `String` gives `(42, true, "second")`. |
| 1076–1100 | [pure.links](../../examples/met/thesis/pure.links), [print_list.links](../../examples/met/thesis/print_list.links), [handlers.links](../../examples/met/thesis/handlers.links) | The cheat sheet repeats the interface, absolute function and relative handler examples. Its `Fail` puts `forall a::Abs` on the operation signature. `all` discards the failing branch and returns `[42]`. |

### Fresco effect and data examples

Source paths are relative to the Fresco artefact at revision
`333738dbe9da1dcd094a6b2c2c9dbb9eec701ea4`. SmallLinks paths are
relative to `examples/met/fresco-effects/`.

| Fresco source | SmallLinks file | Result or reason for exclusion |
| --- | --- | --- |
| `README.md:74–105` | `find_mask_paper.links` | `collected` is `[1, 2, 3]` and `found` is `Just(3)`. Includes the collector, ambient iterator and first-match search. |
| `tests/pass/effectful-empty-list.mle` | `effectful-empty-list.links` | `([], [])` at `(List Int, List Bool)`. The empty list has a polymorphic modal type. |
| `tests/pass/effectful-list.mle` | `effectful-list.links` | `[1]`. A list with a fixed context stores a callback that invokes `Yield`. |
| `tests/pass/effects-exchange.mle` | `effects-exchange.links` | `[1, 2, 3, 1, 2, 1, 2, 3, 1, 3]`. All four positive exchanges work with ordinary SmallLinks interfaces. The reference declares `e3` with `eff#`, whose row-head condition has no SmallLinks counterpart. |
| `tests/pass/extend-absolute-mod.mle` | `extend-absolute-mod.links` | `42`. Converts an absolute pure callback to one typed under `Gen`. |
| `tests/pass/find_mask_paper.mle` | `find_mask_paper.links` | `observed` is `(Just(2), [1, 2])`. The enclosing handler receives both predicate yields and the search stops at the first match. |
| `tests/pass/fresco.mle` | `fresco.links` | `((42, true), (42, true), (42, true))`. Exercises a higher-rank parameter with an annotation, one supplied by an expected type, and a producer with quantification inside an absolute modality. |
| `tests/pass/handle-do-mono.mle` | `handle-do-mono.links` | `()`. Handles a direct call of a monomorphic operation. |
| `tests/pass/handle-do-param-mono.mle` | `handle-do-param-mono.links` | `()`. Infers the interface parameter `Int` from a direct operation call. |
| `tests/pass/handle-fun-param.mle` | `handle-fun-param.links` | `()`. Handles a callback whose relative context supplies `Gen(Int)`. |
| `tests/pass/higher-order-effects.mle` | `higher-order-effects.links` | `([1, 2, 3, 5, 4, 6, 4], [1, 2, 3, 4, 5])`. Runs both FIFO schedulers, with a Boolean fork and a fork that takes a task. The queue is passed to resumptions explicitly. The latter fork has a task payload fixed at `[Trace, Coop]` to satisfy `Abs`. |
| `tests/pass/infer-lambda-do.mle` | `infer-lambda-do.links` | `()`. Infers the interface parameter from the operation in an unannotated thunk passed to a polymorphic callback. |
| `tests/pass/list-map-fold.mle` | `list-map-fold.links` | `([2, 3, 4], 123, 321, [1, 2, 3])`. Shares the context between a list helper and its callback, including an iterator called with `Gen`. |
| `tests/pass/single-yield.mle` | `single-yield.links` | `1`. A function with context `[Gen]` calls `Yield`. |
| `tests/fail/effectful-list-non-value.mle` | `rejected/effectful-list-non-value.links` | `Modal introduction requires a value`. The function call inside the list is available in `Gen`; the resulting list cannot acquire a new absolute modality. |
| `tests/fail/exchange-accidental.mle` | Excluded | Fresco's `eff#` checks that the occurrence is at the head of the remaining row during modality comparison. In SmallLinks distinct interface names commute, and the corresponding two-interface exchange is accepted. |
| `tests/fail/extend-relative-mod.mle` | `rejected/extend-relative-mod.links` | `The modalities require different effect contexts`. An ambient callback cannot acquire a relative `Gen` requirement. |
| `tests/fail/handle-do-param-mismatch.mle` | `rejected/handle-do-param-mismatch.links` | `Expected (), got Int`. The operation clause returns the `Yield` argument where the result must be unit. |
| `tests/fail/handle-fun-mismatch.mle` | `rejected/handle-fun-mismatch.links` | `Expected (), got Int`. The operation clause must also agree with the unit result when the computation is a callback. |
| `tests/fail/leak-effect-paper.mle` | `rejected/leak-effect-paper.links` | `Cannot call a value of type <Gen \|> (_)`. Calling the predicate across the handler lock would let its effects reach the inner handler. |
| `tests/fail/limitation-infer-find-paper.mle` | Excluded | This tests inference for an unannotated callback called under a term mask. SmallLinks has no term mask. The predicate-operation translation invokes the callback in its original context and infers the unannotated definition successfully. |
| `tests/fail/pure-id-fun.mle` | `rejected/pure-id-fun.links` | `must satisfy Abs`. The bare arrow inferred for the lambda does not satisfy the absolute type argument. |
| `tests/fail/relative-to-absolute.mle` | `rejected/relative-to-absolute.links` | `Cannot access f across the change in effect context`. A relative `Gen` callback cannot be returned at the fixed absolute context. |
| `tests/fail/two-do-mismatch.mle` | `rejected/two-do-mismatch.links` | `Expected (\|First\|), got (\|Second\|)`. Both calls must use the same `Gen` instance, so the two closed variant types are incompatible. |

The search examples implement the effect of masking at the predicate
call by requesting evaluation through a `Predicate(a)` operation. Its
handler clause calls the predicate in the caller's context. The loop
runs under both `Gen(a)` and `Predicate(a)`. It keeps the predicate's
evaluation order and early termination, including when the caller
handles a separate `Gen(a)` instance. This preserves shared ambient
contexts without adding a general term mask.

The source higher-order scheduler's `eff# state s` allows the state
type `s` to contain ambient functions. SmallLinks requires absolute
operation payloads and absolute handler state parameters. Passing the
queue through the resumptions as an ordinary argument keeps those
functions in their ambient context. The absolute `Fork` payload fixes
the set of effects available to a child task.

### Larger Fresco programs

Source paths are relative to the Fresco artefact. Each result below is
one component of the corresponding SmallLinks program's output.

| Source | SmallLinks file | Result |
| --- | --- | --- |
| `tests/pass/unix.mle:4–52` | [unix.links](../../examples/met/fresco-programs/unix.links) | `(1, "dead")`. The simulated descriptor `FD(1)` supplies the source's declaration of `stdout`. Exit discards the suffix after it. |
| `tests/pass/unix.mle:54–91` | `unix.links` | Standalone lookup returns `"lucile"`. The session example returns `(0, "alice bob root ")`. A parameterised handler handles `AskUser` and `Su` together and passes the new user to the resumption. The source's `mask<ask>` syntax requires a deferred term mask. |
| `tests/pass/unix.mle:93–121` | `unix.links` | Multi-shot `Fork` returns both statuses `[0, 0]` and collects all of Ritchie's output followed by Hamlet's. |
| `tests/pass/unix.mle:123–152` | `unix.links` | The scheduler resumes two paused branches and returns `([2, 1], "")`. The finished list accumulates each result at the front. |
| `tests/pass/unix.mle:154–167` | `unix.links` | Both statuses are `[0, 0]`. An interruption before each write makes the scheduler alternate the two outputs until Hamlet finishes. |
| `tests/pass/unix.mle:169–184` | `unix.links` | The parameterised `State` interface and state-threading handler return `(40, 42)`. |
| `tests/pass/faux-tt.mle:3–198` | [faux-tt.links](../../examples/met/fresco-programs/faux-tt.links) | Recursive syntax and terms, occurrence checking, a fresh ID supply, polymorphic errors, and a scoped store of metavariables. These support the elaboration demonstrations below. |
| `tests/pass/faux-tt.mle:200–378` | `faux-tt.links` | Capture-avoiding substitution, normalisation and unification. In the hole demonstration unification solves the metavariable with `Type`. |
| `tests/pass/faux-tt.mle:381–468` | `faux-tt.links` | The checked identity elaborates to `Lam(0, Type, Lam(2, Var(0), Var(2)))`. An ascription with a hole infers `(Type, Type)`, the elaborated term and its inferred type. |
| `tests/pass/faux-tt.mle:405–410` | `faux-tt.links` | The upstream `SApp` checks the argument against the codomain. The SmallLinks correction checks it against the domain, then substitutes it into the codomain. The regression applies the identity to `Type` and expects `(Lam(3, Type, Var(3)), Pi(2, Type, Type))` in both default and strict modes. |

### Fresco typing cases

Sources are relative to the artefact's `tests/fresco/`. SmallLinks
programs are relative to `examples/met/fresco-types/`. The artefact
tests 57 files at revision `333738dbe9da1dcd094a6b2c2c9dbb9eec701ea4`.
The table tracks 75 accepted and 20 rejected source subcases, including
the Church-list rejections tested in isolation. A runtime result in
the table refers to the indicated component of the program's output.

| Source and subcase | SmallLinks program and binding | SmallLinks result |
| --- | --- | --- |
| `pass/a1.mle` infer | `choice.links` `inferredSecond` | Inferred curried projection. Returns `42`. |
| `pass/a1.mle` check | `choice.links` `checkedSecond` | Checks the signed projection. Returns `true`. |
| `pass/a2.mle` infer | `choice.links` `inferredChoice` | The identity's type is instantiated. Applying the result returns `42`. |
| `pass/a2.mle` check | `choice.links` `checkedChoice` | Checks at `Id -> Id`. Applying the result returns `true`. |
| `pass/a3.mle` infer | `native-lists.links` `inferredChoice` | Returns a list of two polymorphic identities. |
| `pass/a3.mle` check | `native-lists.links` `checkedChoice` | Checks at `List Id` and has length `2`. |
| `pass/a4.mle` | `choice.links` `selfApply` | Inferred self-application of an annotated polymorphic argument. Applying the result returns `42`. |
| `pass/a5.mle` infer | `choice.links` `inferredAuto` | Infers a function that takes and returns `Id`. Applying the result returns `42`. |
| `pass/a5.mle` check | `choice.links` `checkedAuto` | Checks at `Id -> Id`. Applying the result returns `true`. |
| `pass/a6.mle` | `choice.links` `specialisedAuto` | Infers the result with the outer type argument of `autoPrime` instantiated. Applying it returns `42`. |
| `pass/a7.mle` infer | `choice.links` `inferredAutoChoice` | Infers the higher-rank function type from `auto`. Applying the result returns `42`. |
| `pass/a7.mle` check | `choice.links` `checkedAutoChoice` | Checks at `Id -> Id`. Applying the result returns `true`. |
| `pass/a9.mle` native | `native-list-results.links` `chosenFunction` | Returns a polymorphic identity. Applying it returns `42`. |
| `pass/a9.mle` Church | `church-list-results.links` `chosenFunction` | Returns a polymorphic identity. Applying it returns `42`. |
| `pass/a10.mle` A10a | `application.links` `named` | `(42, true)` from a named argument. |
| `pass/a10.mle` A10b | `application.links` `lambda` | `(42, true)` from a lambda argument. |
| `pass/a10.mle` A10c | `application.links` `viaIdent` | `(42, true)` after applying identity to a higher-rank consumer. |
| `pass/a11.mle` native | `native-list-results.links` `sharedType` | The list supplies the lambda's parameter type. Returns `1`. |
| `pass/a11.mle` Church | `church-list-results.links` `sharedType` | The fold supplies the lambda's parameter type. Returns `1`. |
| `pass/a12.mle` A12a | `application.links` `forward` | `(42, true)` using application. |
| `pass/a12.mle` A12b | `application.links` `backward` | `(42, true)` using reverse application. |
| `pass/a13.mle` A13a | `rank-two.links` `forwardST` | `42` using `app` with a state-polymorphic value. |
| `pass/a13.mle` A13b | `rank-two.links` `backwardST` | `42` using `revapp` with a state-polymorphic value. |
| `pass/b1.mle` B1a native | `native-lists.links` `rest` | Tail retains type `List Id` and has length `1`. |
| `pass/b1.mle` B1b native | `native-lists.links` `first` | Head has type `Id` and returns `42` and `true` at the two uses. |
| `pass/b1.mle` B1c native | `native-lists.links` `one` | Singleton instantiates the identity. Calling its head returns `42`. |
| `pass/b1.mle` B1a Church | `church-lists.links` `rest` | Tail retains type `Church(Id)` and has length `1`. |
| `pass/b1.mle` B1b Church | `church-lists.links` `first` | Head has type `Id` and returns `42` and `true` at the two uses. |
| `pass/b1.mle` B1c Church | `church-lists.links` `one` | Singleton instantiates the identity. Calling its head returns `42`. |
| `pass/b2.mle` native | `native-lists.links` `withName` | Prepends a named identity at type `Id`. Length `3`. |
| `pass/b2.mle` Church | `church-lists.links` `withName` | Prepends a named identity at type `Id`. Length `3`. |
| `pass/b3.mle` native | `native-lists.links` `withLambda` | Prepends a lambda checked at `Id`. Length `3`. |
| `pass/b3.mle` Church | `church-lists.links` `withLambda` | Prepends a lambda checked at `Id`. Length `3`. |
| `pass/b4.mle` native | `native-lists.links` `ints` | Infers integer functions from two singleton calls. Applying them returns `[42, 41]`. |
| `pass/b4.mle` Church | `church-lists.links` `ints` | Infers integer functions from two singleton calls. Applying them returns `[42, 41]`. |
| `pass/b5.mle` native | `native-lists.links` `moreIds` | Appends a singleton at `List Id`. Length `3`. |
| `pass/b5.mle` Church | `church-lists.links` `moreIds` | Appends a singleton at `Church(Id)`. Length `3`. |
| `pass/b6.mle` native | `native-lists.links` `mappedSingleton` | `[(42, true)]` from mapping a higher-rank consumer over a singleton. |
| `pass/b6.mle` Church | `church-lists.links` `mappedSingleton` | A Church singleton of `(42, true)`, converted to `[(42, true)]`. |
| `pass/b8.mle` native | `native-lists.links` `appliedHead` | Calls the polymorphic head and returns `true`. |
| `pass/b8.mle` Church | `church-lists.links` `appliedHead` | Calls the polymorphic head and returns `true`. |
| `pass/beta1.mle` | `application.links` `returnedApp` | `(42, true)` via an application function returned by a lambda. |
| `pass/beta3.mle` | `application.links` `returnedArgument` | `(42, true)` with a higher-rank argument returned by a lambda. |
| `pass/c1b.mle` | `rank-two.links` `useBoth` | An annotated parameter can be used at both types. Returns `(42, true)`. |
| `pass/c1c.mle` | `rank-two.links` `checkedLambda` | The expected type supplies the polymorphic parameter. Returns `()`. |
| `pass/c2.mle` | `rank-two.links` `nestedQuantifiers` | Checks the lambda with a quantifier before each arrow. Returns `42`. |
| `pass/e1b.mle` native | `native-list-results.links` `etaExpanded` | Checks the lambda against a type quantified before its `Int` argument. Applying it returns `true`. |
| `pass/e1b.mle` Church | `church-list-results.links` `etaExpanded` | Checks the lambda against a type quantified before its `Int` argument. Applying it returns `true`. |
| `pass/e2b.mle` | `rank-two.links` `consume` | The signature supplies the higher-rank parameter, returning `(42, true)`. |
| `pass/e3a.mle` | `application.links` `forward` | Same expression as A12a. Returns `(42, true)`. |
| `pass/e3b.mle` | `application.links` `frozenArgument` | Freezing supplies the polymorphic parameter to the lambda. Returns `(42, true)`. |
| `pass/e4a.mle` native | `native-lists.links` `mappedName` | `[(42, true), (42, true)]` from mapping a named consumer. |
| `pass/e4a.mle` Church | `church-lists.links` `mappedName` | Maps a named consumer. Converts to `[(42, true), (42, true)]`. |
| `pass/e4b.mle` native | `native-lists.links` `mappedLambda` | `[(42, true), (42, true)]` from mapping a lambda. |
| `pass/e4b.mle` Church | `church-lists.links` `mappedLambda` | Maps a lambda. Converts to `[(42, true), (42, true)]`. |
| `pass/e6.mle` | `application.links` `returnedPartial` | `(42, true)` after returning a partial application from a lambda. |
| `pass/e7.mle` | `application.links` `passedToLambda` | A frozen identity gives the lambda a polymorphic parameter. Returns `(42, true)`. |
| `pass/f1.mle` native | `native-lists.links` `mappedTwice` | `[(true, 42), (true, 42)]` from mapping a lambda that calls each element at two types. |
| `pass/f1.mle` Church | `church-lists.links` `mappedTwice` | Maps a lambda that calls each element at two types. Converts to `[(true, 42), (true, 42)]`. |
| `pass/f2.mle` | `application.links` `viaApp` | Calls both instantiations via `app`. Returns `(true, 42)`. |
| `pass/f4.mle` | `application.links` `direct` | Calls both instantiations via direct application. Returns `(42, true)`. |
| `pass/f5.mle` | `application.links` `checkedPair` | Checks the function against the pair's expected type. Observed as `(42, 42)`. |
| `pass/f6.mle` | `church-list-results.links` `chosenList` | Infers a fold with its accumulator type instantiated. Counting the elements returns `2`. |
| `pass/f7.mle` Church | `church-list-results.links` `chosenHead` | Freezing retains the Church fold's quantifier. Applying the selected identity returns `42`. |
| `pass/f7.mle` native | `native-list-results.links` `chosenHead` | The native list retains its polymorphic element type. Applying the selected identity returns `42`. |
| `pass/f8.mle` native | `native-list-results.links` `fromIntCallback` | The callback returns `List Id`. Its consumer returns `(42, true)`. |
| `pass/f8.mle` Church | `church-list-results.links` `fromIntCallback` | Returns a fold with an instantiated accumulator. Counting returns `2`. |
| `pass/f9.mle` native | `native-list-results.links` `fromPairCallback` | The callback returns a pair with `List Id` in the second component. Its consumer returns `(42, true)`. |
| `pass/f9.mle` Church | `church-list-results.links` `fromPairCallback` and `church-pair-result.links` | Folding the result at `Int` returns `2`. The standalone expression retains an unconstrained accumulator and passes with frontend rechecking and strict IR checking enabled. |
| `pass/f10.mle` native | `native-list-results.links` `fromIdCallback` | A callback takes `Id` and returns `List Id`. Its consumer returns `(42, true)`. |
| `pass/f10.mle` Church | `church-list-results.links` `fromIdCallback` | A callback takes `Id` and returns a fold with an instantiated accumulator. Counting returns `2`. |
| `pass/f11a.mle` native | `native-list-results.links` `checkedCall` | The expected type of the singleton retains `Id`. Returns `(42, true)`. |
| `pass/f11a.mle` Church | `church-list-results.links` `checkedCall` | The expected type of the singleton retains `Id`. Returns `(42, true)`. |
| `pass/f11b.mle` native | `native-list-results.links` `frozenCall` | The frozen identity retains `Id` in the bound singleton. Returns `(42, true)`. |
| `pass/f11b.mle` Church | `church-list-results.links` `frozenCall` | The frozen identity retains `Id` in the bound singleton. Returns `(42, true)`. |
| `fail/a8.mle` | `rejected/choice-polymorphic-result.links` | Rejects the mismatch between a polymorphic result and an instantiated result of `autoPrime`. |
| `fail/b7.mle` native | `inference-differences.links` `mappedHeads` | SmallLinks accepts the inferred list of polymorphic identities. Its consumer returns `(42, true)`. |
| `fail/b7.mle` Church | `rejected/church-map-head.links` | Rejects the element type of the nested fold without the expected polymorphic identity type. |
| `fail/c1a.mle` | `rejected/unannotated-polymorphic-parameter.links` | Rejects the `Bool` call after inferring an `Int` parameter. |
| `fail/e1a.mle` native | `rejected/list-quantifier-placement.links` | Rejects the quantifier in `h`'s result against a type quantified before its argument. |
| `fail/e1a.mle` Church | `rejected/church-quantifier-placement.links` | Rejects the quantifier in `h`'s result against a type quantified before its argument. |
| `fail/e2a.mle` | `rejected/unannotated-poly-consumer.links` | Rejects the unknown parameter type where `poly` needs `Id`. |
| `fail/e3b.mle` | `rejected/application-unfrozen-argument.links` | Rejects the inferred parameter because a quantified variable would escape its scope. |
| `fail/e5a.mle` native | `inference-differences.links` `consumeHead` | SmallLinks infers that the composition takes `List Id`. Applying it returns `(42, true)`. |
| `fail/e5a.mle` Church | `inference-differences.links` `consumeChurchHead` | SmallLinks infers that the composition takes `Church(Id)`. Applying it returns `(42, true)`. |
| `fail/e5b.mle` native | `rejected/unannotated-list-parameter.links` | Rejects the unknown parameter type where `head` needs `List Id`. |
| `fail/e5b.mle` Church | `rejected/unannotated-church-parameter.links` | Rejects the unknown parameter type where `churchHead` needs a polymorphic fold. |
| `fail/e7.mle` | `rejected/lambda-unfrozen-argument.links` | Rejects the inferred parameter because a quantified variable would escape its scope. |
| `fail/f2.mle` | `rejected/apply-unfrozen-identity.links` | Rejects the `Int` call after inferring a `Bool` parameter. |
| `fail/f3.mle` native | `inference-differences.links` `mappedIds` | SmallLinks instantiates the mapping identity at `Id`. Its consumer returns `(42, true)`. |
| `fail/f3.mle` Church | `inference-differences.links` `mappedChurchIds` | SmallLinks instantiates the mapping identity at `Id`. Its consumer returns `(42, true)`. |
| `fail/f4.mle` | `rejected/call-unfrozen-identity.links` | Rejects the `Bool` call after inferring an `Int` parameter. |
| `fail/f7.mle` | `inference-differences.links` `chosenHead` | SmallLinks accepts the unfrozen Church argument. The result is an identity called at `Int` and `Bool`, yielding `(42, true)`. |
| `fail/f11b.mle` native | `rejected/bound-singleton.links` | Rejects the list of instantiated identities where a list of polymorphic identities is required. |
| `fail/f11b.mle` Church | `rejected/bound-church-singleton.links` | Rejects the fold over instantiated identities where a fold over polymorphic identities is required. |

The commented-out `check` proposals in `pass/a4.mle`, `pass/a6.mle`,
`pass/a9.mle` and `fail/a8.mle` are inactive in the artefact. Standalone
`val` declarations were supplied with definitions for the runnable
examples. In A13 the `Test` constructor carries the result `a`, so
`runST` can return that value while the unused state type `s` remains
universally quantified.

## Example verification

The retest used checkout revision
`02b3e4abf605de8f8be70307b1483fef12b6b39b` with the example path and
registration updates. The compiler and elaborator fixes are included
through `cf07fd2d`. See the
[combined compiler checks](PLAN.md#milestone-610-checks) for the full
regression and IR unit suites. The logs and temporary configurations
below are in `/private/tmp/smalllinks-met-example-retest.YrzBhK/`.

| Command | Result | Log |
| --- | --- | --- |
| `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk make all-ci` | Built the compiler and updated the example installation files. | `final-build.log` |
| `./links` on the Church callback and minimal `fromPair` | Both retained their inferred type with default settings, frontend rechecking, strict IR and both checks together. | `direct-probes.log` |
| `./links --set=types_pretty_printer_engine=old` and `./links --set=types_pretty_printer_engine=roundtrip` on the ten-element tuple | Both printers put `Bool` second and `String` tenth. | `direct-probes.log` |
| `./links` on `faux-tt.links` with default and strict flags | Both original demonstrations and the application of the identity to `Type` returned the results in the inventory. | `direct-probes.log` |
| `./test-harness tests/met_examples.tests`, once by default and once with `strict.config` | All 32 runtime examples gave the expected output in each run. | `runtime-default.log`, `runtime-strict.log` |
| `./test-harness tests/typecheck_examples.tests` and `./test-harness strict-typecheck.tests` with the temporary strict configuration | All 94 entries passed in each run, including 28 expected MET rejections. | `typecheck-default.log`, `typecheck-strict.log` |
| `./test-harness tests/recheck_frontend_transformations.tests` and `./tests/roundtrippable_types.testscript` | Six frontend regressions and 34 type print-and-reparse checks passed. | `frontend-regressions.log`, `print-and-reparse.log` |
| `./tests/validate_typecheck_testfile.testscript`, `make rule-check`, `git diff --check` and the document and manifest checks | Registrations, source checks and links passed. The document check also scanned for tabs because GNU find was unavailable. | `example-registration.log`, `rule-check.log`, `diff-check.log`, `documents.log` |
| `opam exec -- dune install --profile=ci --prefix="$prefix" links` and `./tests/check-install.sh "$prefix/bin/linx"` | Installation checks passed. All 60 example files and the README matched the checkout. The installed Church example passed with both configurations from outside the repository. | `install.log`, `install-check.log`, `installed-examples.log` |

The original Fresco runs passed all 25 effect and data tests and 57
typing tests. See `/tmp/met-fresco-effects-reference.log` and
`/tmp/met-fresco-artifact-tests.log`.
