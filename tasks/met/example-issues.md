# Modal effect example notes

These notes use SmallLinks revision
`7b764a87e6414b46de8feb00c2de0c8c704dbca2` and Fresco revision
`333738dbe9da1dcd094a6b2c2c9dbb9eec701ea4`.
See [examples.md](examples.md#example-source-coverage) for the source
inventory and examples that depend on deferred features.

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
