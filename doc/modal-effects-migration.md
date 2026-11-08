# Migrating to modal effects

This guide applies to the `modal-effects` branch. The
[specification](modal-effects-spec.md) gives the language rules;
[PLAN.md](../PLAN.md) records completed and postponed work.

## Select the frontend

| Option | Frontend |
|---|---|
| No selector | Fresco |
| `--fresco` | Fresco |
| `--set=fresco=false` | Legacy inference |

These choices apply to batch input, the REPL and compilation. Fresco errors
stop the selected input; they never select legacy inference automatically.
An explicit `--set=fresco=...` takes precedence over direct selector flags.
Use separate processes when comparing the two frontends.

Fresco loads `FrescoPrelude` by default. `--set=prelude=path` replaces that
prelude; `--set=prelude=tests/empty_prelude.links` leaves the primitives.
Legacy inference loads the original prelude and accepts legacy effect arrows. Its
compile mode uses source files; legacy `-e` inputs are evaluated before file
compilation. Fresco compile mode checks and compiles `-e` inputs without
evaluating them. See [frontend behaviour](modal-effects-spec.md#9-initial-effect-context).

## Migrate declarations and handlers

1. Apply the [syntax changes](modal-effects-spec.md#81-required-source-changes)
   to signatures and aliases as well as expressions. Use `List A` and
   `List (List A)` for lists and nested lists.
2. Group related operations in a named effect declaration. Give every
   operation argument and result an absolute type. A function payload can
   carry an explicit absolute modality.
3. Give each handler one clause per operation in its effect. Put argument
   alternatives in a `switch` within that clause.
4. Use qualified names when visible effects share an operation's short name.
   Nest handlers to handle several effect groups.
5. Supply effect arguments explicitly when they are polymorphic or modal.
   Omitted handler arguments are inferred as monotypes.

For example, save this program as `reader.links`:

```links
effect Reader(a::Abs) { Ask : () => a; }

sig ask : forall a::Abs. modal [Reader(a)] (() -> a)
fun ask() { do Reader.Ask }

var answer = handle <Reader(Int)> (ask()) {
  case x -> x
  case <Ask => k> -> k(42)
};
print(intToString(answer))
```

The handler can also omit `<Reader(Int)>`; its clause and computation infer
the effect and its `Int` argument. The
[handler rules](modal-effects-spec.md#23-handlers) describe inference,
completeness and qualification. Repeated occurrences of one effect retain
their order and type arguments; lookup uses the first occurrence.

## Preserve function contracts

Use `->` for ordinary functions and `-@` for linear functions. Function arrows
use ambient effects. An absolute modality fixes an effect context; a relative
modality changes the caller's context. External primitives such as `print`
require `Wild`. Follow the
[arrow migration rules](modal-effects-spec.md#82-migrating-effect-annotated-arrows)
for callbacks, returned functions and curried signatures.

Keep callbacks contextual when they share the caller's effects. For example:

```links
sig applyTwice : forall a. ((a) -> a, a) -> a
fun applyTwice(f, x) { f(f(x)) }

effect Reader { Ask : () => Int; }
handle <Reader> (applyTwice(fun(x) { x + do Ask }, 0)) {
  case x -> x
  case <Ask => k> -> k(21)
}
```

This returns `42`. Putting `modal []` around the callback type would require
a pure callback. Global function signatures receive an implicit outer
`modal []` unless they already supply an absolute modality.

Supply signatures for recursive functions and `forall` annotations where
polymorphic reuse is required. Local bindings do not generalise implicitly.
`freeze(e)` retains supplied polymorphic structure; it still checks modal
access. See [bindings and annotations](modal-effects-spec.md#52-bindings-and-annotations).

Keep ordinary kinds as well as modal kinds. `Abs` constrains effects and
does not make a linear value unlimited. Alias parameters and recursive
declarations must preserve their original ordinary requirements. When an
application must guess an unknown callable type, it chooses an ordinary
arrow. A returned linear function may need an annotation or an intermediate
binding before application. See
[existing constructs](modal-effects-spec.md#53-existing-links-constructs-and-interactive-use).

Some interfaces have independent effects for several callbacks or returned
functions. Preserve their full contracts. A specialised fixed-effect use does
not migrate the general interface. Keep their recorded compatibility routes;
the [contract inventory](modal-effects-design.md#signatures-with-independent-effect-variables)
and [postponed list](../PLAN.md#postponed-work) identify these cases.

## Check and execute

Run commands from the repository root. Enable handlers when starting each
process:

```sh
./links --enable-handlers reader.links
./links --enable-handlers --set=typecheck_only=true reader.links
./links --enable-handlers --compile -o reader.js reader.links
node reader.js
```

The interpreter and JavaScript runs print `42`. Deep handlers execute on both
runtimes. Shallow handlers execute in the interpreter and are rejected by the
JavaScript compiler. A shallow resumption needs another handler for its
operations, as in [the shallow example](../tests/fresco_modal/shallow11.links).
Modal types and freezing are erased before execution.

To check typed lowering and the shared IR during an interpreter run:

```sh
./links --enable-handlers --set=recheck_frontend_transformations=true \
  --set=typecheck_ir=true --set=fail_on_ir_type_error=true reader.links
```

Keep each regression suite's existing feature settings and intended error
causes. The [backend checks](../tests/fresco_backend.py) run actual interpreter
and JavaScript executions with default and explicit Fresco selection, with
optimisation disabled and enabled. The
[verification record](../PLAN.md#latest-task-and-verification) links the full
commands, source revisions and logs.

Database support, control-flow linearity, session failure, higher-order effects
and the other [postponed work](../PLAN.md#postponed-work) remain outside this
migration. The [five D7 implementation choices](../PLAN.md#d7-choices-awaiting-review)
still await user review.
