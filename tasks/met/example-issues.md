# Modal effect example notes

These notes use SmallLinks revision
`7b764a87e6414b46de8feb00c2de0c8c704dbca2` and Fresco revision
`333738dbe9da1dcd094a6b2c2c9dbb9eec701ea4`.
See [examples.md](examples.md#example-source-coverage) for the source
inventory and examples that depend on deferred features.

## SmallLinks defects

### Frontend rechecking fails for a callback pair with an unconstrained result

`examples/met/fresco-types/blocked/church-pair-result.links` translates
the Church subcase of `tests/fresco/pass/f9.mle`. The artefact accepts
this application with a monomorphic, unresolved fold accumulator type.
SmallLinks accepts it by default and with IR checking enabled. Frontend
rechecking rejects the lambda `fun(x) { (x, churchIds) }` with
`Type abstraction needs a type annotation`.

Commands, run from the SmallLinks repository root:

```sh
./links examples/met/fresco-types/blocked/church-pair-result.links
./links --set=recheck_frontend_transformations=true examples/met/fresco-types/blocked/church-pair-result.links
./links --set=typecheck_ir=true --set=fail_on_ir_type_error=true examples/met/fresco-types/blocked/church-pair-result.links
```

The first and third commands print
`fun : (a) -> ((forall b.[] ((b) -> b)) -> (a) -> a) -> a`.
The second command exits with status 1. The expected result is
the same successful check in all three modes. The full artefact
and SmallLinks runs are in
`/tmp/met-fresco-artifact-pass-types.log`,
`/tmp/met-fresco-types-validation/default-church-pair-result.links.log`
and `/tmp/met-fresco-types-validation/strict-church-pair-result.links.log`.

The failure reproduces with the prelude identity in place of the fold:

```links
sig fromPair : forall a. (forall b. b -> (b, a)) -> a
fun fromPair(f) { f(42).2 }

fromPair(fun(x) { (x, id) })
```

Run `./links /tmp/met-fresco-types-f9-minimal.links` and
`./links --set=recheck_frontend_transformations=true /tmp/met-fresco-types-f9-minimal.links`.
The default and IR-only checks print `fun : [] ((a::Any) -> a::Any)`.
Frontend rechecking reports the same type abstraction error.
See `/tmp/met-fresco-types-f9-minimal.log`.

The Church example also runs the original call in
`examples/met/fresco-types/church-list-results.links`. Folding the
result with an `Int` accumulator makes the same call pass frontend
rechecking and produces `2`.

### Tuple types print position 10 before position 2

This appeared when grouping runtime observations into a tuple. The
examples use nested tuples instead.

```sh
./links -e '(1, true, 3, 4, 5, 6, 7, 8, 9, "ten")'
```

The tenth value is a string. The type printer shows
`(Int, String, Bool, Int, Int, Int, Int, Int, Int, Int)`. The expected
type is `(Int, Bool, Int, Int, Int, Int, Int, Int, Int, String)`.
See `/tmp/met-fresco-types-tuple-print.log`.

## Fresco defects

### Application checks the wrong type in the example elaborator

This defect is in the example algorithm in Fresco's
`tests/pass/faux-tt.mle:405–410`. The `SApp` branch checks the
argument against the function's codomain before substitution. The
argument should be checked against the domain. The port preserves
the source rule. Both shipped elaboration demonstrations pass.

To reproduce in SmallLinks, replace the demonstration after
`# Check the identity` in `faux-tt.links` with this expression and
save the program as `faux-tt-app.links`.

```links
inferTopLevel(SApp(SLam("A", Just(SType),
                       SLam("x", Just(SVar("A")), SVar("x"))),
                   SType))
```

Run `./links faux-tt-app.links`. Applying the identity to the type
`Type` should return a function of type `(x : Type) -> Type`.
The elaborator reports `error: type mismatch` and raises
`Runtime error: Elaboration failed`. Checking the domain in a
temporary copy produces `(Lam(3, Type, Var(3)), Pi(2, Type, Type))`.
The [example](../../examples/met/fresco-programs/faux-tt.links)
can encounter this on an object-language application whose argument
has the domain type and fails the codomain check.

Logs for the strict checks are
`/private/tmp/smalllinks-met-examples/faux-tt-app.log` and
`/private/tmp/smalllinks-met-examples/faux-tt-app-domain.log`.

### The Fresco evaluator loads eager definitions in reverse order

This defect is in the reference Fresco interpreter at
`333738dbe9da1dcd094a6b2c2c9dbb9eec701ea4`. The source
`tests/pass/unix.mle` passes its type check, but running it with
`--eval` reports `missing a definition for symbol basicIO`.
The evaluator processes a list built by prepending each checked
definition. It thus evaluates eager definitions before earlier
dependencies. The source also declares `stdout` without a value
and supplies no `main` function. The SmallLinks port uses the
simulated descriptor `FD(1)` and a final expression.

```text
type unit = Unit
let earlier = 1
let later = earlier
val main : [](unit -> unit)
let main u = ()
```

Run `bin/met.exe --eval reference-order.mle` from a built copy of
the Fresco artefact. The program should evaluate `main` and exit
successfully. It exits with status 1 and reports
`missing a definition for symbol earlier`. Logs are
`/private/tmp/smalllinks-met-examples/reference-order.log` and
`/private/tmp/smalllinks-met-examples/reference-unix.log`.

## Unsupported features

### Fresco `eff#` modifier

Fresco `tests/fail/exchange-accidental.mle` checks that the interface
with `eff#` occurs at the head of the remaining effect row. Its
checker rejects the changed order. In SmallLinks, instances with
different interface names commute, so the corresponding conversion
typechecks.

```links
effect E1 { O1 : () => (); }
effect E2 { O2 : () => (); }

sig id : ([E2, E1] (() -> ())) -> [E1, E2] (() -> ())
fun id(f) { f }
```

Running `./links repro.links` exits successfully. The reference
rejection and the SmallLinks commands and results appear in
`/tmp/met-fresco-effects-reference-negatives.log` and
`/tmp/met-fresco-effects-exclusions.log`. The positive interface
exchange example translates to
[effects-exchange.links](../../examples/met/fresco-effects/effects-exchange.links).
The `eff#` rejection is excluded because SmallLinks has no such
interface modifier.

### Term-level masks

Fresco `tests/fail/limitation-infer-find-paper.mle` cannot infer an
unannotated callback called under a term mask. SmallLinks defers
term-level masks. To check the translated behaviour,
remove the signature of `Search.find` in
[find_mask_paper.links](../../examples/met/fresco-effects/find_mask_paper.links)
and run `./links repro.links`. The handler calls its predicate in
the original context, so SmallLinks infers the function successfully.
The `observed` binding evaluates to `(Just(2), [1, 2])`. The commands and
results are in `/tmp/met-fresco-effects-exclusions.log`.
The tutorial's masked `find` uses the same translation.

## Typing differences

### Partial switches constrain closed variant types

This is a SmallLinks typing constraint. It affects `foldSpine` and
`unifyAt` in [faux-tt.links](../../examples/met/fresco-programs/faux-tt.links).
The Fresco version omits cases that its callers cannot reach. In
SmallLinks, a switch with only constructor patterns can constrain the
scrutinee to the alternatives it lists. Both functions supply an
explicit failure for the remaining constructors.

```links
typename Term = mu t. (| Var:Int | Lam:(t, t) | App:(t, t) |);

sig fold : (Term, Int) -> Int
fun fold(term, count) {
  switch (term) {
    case Var(x) -> x + count
    case App(m, _) -> fold(m, count + 1)
  }
}

fold(App(Var(40), Var(0)), 1)
```

The source-style partial match is expected to return `42` for this
input. SmallLinks rejects it with
`Pattern type ... does not match (Lam-)`. Adding
`case _ -> error("Expected a neutral term")` makes the call return
`42 : Int`. Run `./links repro.links`. The default and strict results
are in `/private/tmp/smalllinks-met-examples/recursive-pattern-default.log`
and `/private/tmp/smalllinks-met-examples/recursive-pattern-strict.log`.

### Absolute operation payloads and ambient resumptions

The state operation of Fresco's
`tests/pass/higher-order-effects.mle` uses `eff#` and stores
resumptions that depend on the current context. SmallLinks requires
absolute operation payloads. An absolute annotation on a thunk also
introduces a lock, so it cannot close over an ambient resumption.

```links
effect Pause { Suspend : () => (); }

sig pause : (<Pause> (() -> ())) -> [] (() -> ())
fun pause(action) {
  handle(action()) {
    case <Suspend => k> -> (fun() { k(())() } : [] (() -> ()))
    case () -> fun() { () }
  }
}

pause(fun() { do Suspend })()
```

Run `./links repro.links`. Under SmallLinks's lock rule the capture
is rejected with `Cannot access k across the change in effect context`,
as shown in `/private/tmp/smalllinks-met-examples/absolute-resumption.log`.
The full queue attempt and diagnostic are in
`/tmp/met-fresco-effects-queue-direct.links` and
`/tmp/met-fresco-effects-queue-direct.log`. The runnable
[schedulers](../../examples/met/fresco-effects/higher-order-effects.links)
thread the queue through resumptions as an ordinary argument.

### SmallLinks accepts six rejected artefact subcases

`examples/met/fresco-types/inference-differences.links` keeps the
original expressions at unannotated bindings and uses their results.
The artefact rejects these six subcases. SmallLinks accepts the isolated
expressions with ambient function types, as well as the runnable
examples using signed global helpers with absolute function types.

| Original subcase | Expression | SmallLinks inferred type with ambient helpers |
| --- | --- | --- |
| B7 native | `fmap(head)(single(ids))` | `List Id` |
| E5a native | `compose(poly)(head)` | `List Id -> (Int, Bool)` |
| E5a Church | `compose(poly)(churchHead)` | `Church(Id) -> (Int, Bool)` |
| F3 native | `fmap(ident)(ids)` | `List Id` |
| F3 Church | `churchMap(ident)(churchIds)` | `Church(Id)` |
| F7 Church | `churchHead(choose(churchNil)(churchIds))` | `Id` |

In the ambient versions, `Id` means `forall a. a -> a`. In F7
SmallLinks obtains the polymorphic Church fold type from the expected
type of `churchHead`'s argument. The Church B7 subcase still rejects.

```sh
./links examples/met/fresco-types/inference-differences.links
./links --set=recheck_frontend_transformations=true --set=typecheck_ir=true --set=fail_on_ir_type_error=true examples/met/fresco-types/inference-differences.links
```

Both commands print six results of `(42, true)`. See
`/tmp/met-fresco-types-validation/strict-inference-differences.links.log`
and `/tmp/met-fresco-types-raw-differences.log`. Each ambient comparison
can be run with the same strict options on the corresponding path in
`/tmp/met-fresco-types-probes/raw-fail-*.links`.
