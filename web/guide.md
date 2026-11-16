# SmallLinks language guide

SmallLinks is a functional language with type inference and effect
handlers. Open a listing in the playground. **Check** shows the
inferred type and **Run** also shows the result and any printed output.
Each run starts with the standard prelude.
[Full SmallLinks guide](../tasks/met/GUIDE.md).

## Basics

A program contains declarations and may end with an expression. The
value of that expression is the program's result. A `#` starts a comment
that runs to the end of the line.

The following expression returns `(42, "yes")`. An `if` tests a `Bool`
and evaluates the chosen branch. Both branches must have the same type.

```links
(6 * 7, if (3 < 4) "yes" else "no")
```

Use `var name = expression;` to bind a value. A block in braces returns
its final expression. Here `n` is local to the block, which returns `25`.

```links
{
  var n = 5;
  n * n
}
```

The factorials example uses `product([1..i])` to multiply the integers
from `1` to `i`. It returns the factorials of `1` to `10` as records, ending
with `(f = 3628800, i = 10)`. [Try factorials](../examples/factorial.links).

## Data and patterns

A tuple `(20, "start")` groups values that can have different types.
A record `(x=20, y=22)` names its fields. Project a field with `point.x`
or use a pattern to bind several fields. This block returns `42`.

```links
{
  var point = (x=20, y=22);
  var (x=first, y=second) = point;
  first + second
}
```

Lists contain elements of one type. Use `[]` for the empty list, `::`
to prepend an element and `++` to join two lists. Variant constructors
such as `Nothing` and `Just(42)` start with a capital letter and can
carry a value. A `switch` takes the first matching case. In this fragment,
`head :: _` matches a non-empty list and `_` ignores the tail. The switch
returns `42`.

```links
switch (Just([42, 99])) {
  case Just(head :: _) -> head
  case _ -> 0
}
```

The list example uses `[]` and `x :: rest` cases to map and fold over
`[1, 2, 3]`. The result `([2, 3, 4], 123, 321, [1, 2, 3])` contains the
mapped list, the left and right folds, and the values collected by a handler.
[Try map and folds](../examples/met/fresco-effects/list-map-fold.links).

## Functions and types

Define a named function with `fun name(x, y) { body }` or write
`fun(x) { body }` for an anonymous function. Calls evaluate the
arguments before the body. Each parameter group takes a separate
call. Here `add(2)` returns a function that remembers `2`, and
`map` applies it to each list element to give `[12, 22]`.

```links
fun add(x)(y) { x + y }
map(add(2), [10, 20])
```

SmallLinks infers most types. Write `sig f : T` before a definition
to give it a signature. A `forall a` quantifies the type variable `a`.
An arrow follows one argument group, so `(Int, Bool) -> Int` takes two
arguments and `((Int, Bool)) -> Int` takes a single tuple. Here `identity`
can be used at both `Int` and `Bool`, yielding `(42, true)`.

```links
sig identity : forall a. [] (a -> a)
fun identity(x) { x }
(identity(42), identity(true))
```

A function that takes a polymorphic argument can use `forall` in the
argument type. The rank-two example calls such an argument at `Int`
and `Bool` and returns `(42, 42, (42, true), (), 42, (42, true))`.
[Try rank-two polymorphism](../examples/met/fresco-types/rank-two.links).

The Church numerals example uses `typename` to name a polymorphic
function type `Nat`. It adds two Church numerals and converts the
result to the integer `4`. [Try Church numerals](../examples/church.links).

## Modules and imports

Use `module Name { ... }` to group declarations. Qualify a member as
`Name.member`, or use `open Name;` to bring its names into scope.
The expression `Double.apply(21)` below returns `42`.

```links
module Double {
  fun apply(n) { n * 2 }
}

Double.apply(21)
```

Use `import Name;` to load another file as a module. Lower-case the
first letter of `Name` and append `.links` to get the file name.
When an example is loaded, the playground searches the bundled standard
library first, then the example's directory.

The caller below imports `shallow_state.links` and returns
`(0, [0, 1, 2, 3, 4])`. The first component is the final counter value,
and the list records the state changes in reverse order.

```links example=examples/handlers/module_import.links
import Shallow_state;

# Count down from five and collect the new state after each step.
Shallow_state.unitTest(5)
```

[Open the caller](../examples/handlers/module_import.links) or
[read the imported module](../examples/handlers/shallow_state.links).

## Effects and handlers

Declare operations in an `effect` interface. In `Choose : () => Bool`,
the operation takes no arguments and returns a `Bool`. Use `do Choose`
to invoke it or `do Op(args)` to pass arguments. The handler catches
`Choose` and `k` resumes the computation with a chosen value. Running
the two resumptions below gives `[1, 2]`.

```links
effect Choice { Choose : () => Bool; }

handle(if (do Choose) 1 else 2) {
  case <Choose => k> -> k(true) ++ k(false)
  case n -> [n]
}
```

A handler needs a clause for every operation in each interface it
handles. The return clause `case n -> [n]` turns each completed
computation's result into a list. A deep handler, written `handle`,
reinstalls itself when `k` resumes. A shallow handler, written
`shallowhandle`, resumes in the enclosing effect context. The state
module uses recursive calls to install another shallow handler around
each resumption.
See [Modules and imports](#modules-and-imports).

An operation clause can omit the resumption. In the single-yield
example, `case <Yield(n)> -> n` ends the handled computation at its
first `Yield` and returns `1`.
[Try single yield](../examples/met/fresco-effects/single-yield.links).

## Modal types and linearity

A function type can specify which effects are available to its body.
`[E] T` fixes the context of `T` to `E`, and `[] T` fixes it to the
empty context. `<E> T` adds `E` to the current context. A mask such as
`<Reader |> T` removes the newest `Reader` instance from the context
used to check `T`.

In this fragment, `withAsk` handles `Reader` itself and its callback
type makes `Ask` available in the supplied function. The handler
resumes with `42`, so the call returns `43`.

```links
effect Reader { Ask : () => Int; }

sig withAsk : [] ((<Reader> (() -> Int)) -> Int)
fun withAsk(action) {
  handle(action()) { case <Ask => k> -> k(42) }
}

withAsk(fun() { do Ask + 1 })
```

Operation clauses run in the enclosing context. In the search example,
the `Test` clause calls the predicate there, so the predicate's own
`Yield` operations reach the caller's handler. The program returns
`([1, 2, 3], Just(3), (Just(2), [1, 2]))`.
[Open the search example](../examples/met/fresco-effects/find_mask_paper.links).

A function returned from a handler keeps its effect requirements.
The handler results example runs a delayed state update under a
second handler. It returns `(52, (42, true, "second"))`, with `52`
as the new state and the remaining values chosen by returned functions.
[Try handler results](../examples/met/thesis/handler_results.links).

Use `linfun` to create a linear function. Its type uses `-@`. A linear
local binding or parameter must be used once on each branch of its
scope. This block returns `42`.

```links
{
  var next = linfun(n) { n + 1 };
  next(41)
}
```

The linear list example takes apart a recursive variant, consumes
each element by wrapping it in a new linear function and returns
`LinCons(fun, LinNil)`. [Try linear map](../examples/linearList.links).
