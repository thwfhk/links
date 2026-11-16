# SmallLinks language guide

SmallLinks extends a core subset of [Links](https://links-lang.org/) with
[modal effect types](https://dl.acm.org/doi/10.1145/3720476) and
[Fresco type inference](https://arxiv.org/abs/2607.16061).

Open a listing in the playground.
**Check** shows the inferred type. **Run** also shows the result and any
printed output. Each run starts with the standard prelude.

AI Disclosure: This project is fully vibe-coded.

## Basics

A program contains declarations and may end with an expression. The
value of that expression is the program's result. A `#` starts a comment
that runs to the end of the line.

An `if` tests a `Bool` and evaluates the chosen branch. Both branches
must have the same type. This expression returns `(42, "yes")`.

```links
(6 * 7, if (3 < 4) "yes" else "no")
```

Use `var name = expression;` to evaluate an expression and bind its
value. A binding lasts to the end of its block or file. A new binding
with the same name shadows the earlier one. A block evaluates its
contents in order and returns its final expression. An expression
followed by a semicolon in a block must have type `()`. Here `n` is
local to the block, which returns `25`.

```links
{
  var n = 5;
  n * n
}
```

| Type | Values and operations |
| --- | --- |
| `()` | `()` is the unit value. It is useful when a computation has no other result to return. |
| `Bool` | `true` and `false`. Use `not(b)`, `a && b` and `a \|\| b`. The last two evaluate the right operand only when needed. |
| `Int` | `42` and `-3`. Use `+`, `-`, `*` and `/`. |
| `Float` | `3.5` and `-.0.5`. Use `+.`, `-.`, `*.` and `/.`. |
| `Char` | `'a'` and `'\n'`. Use `ord(c)` to get the integer code of a character. |
| `String` | `"hello"` and `"line\n"`. Use `s ^^ t` to join strings. |
| `DateTime` | `intToDate(0)` converts the Unix epoch. Use `showUTC(d)` to format a date in UTC. |

Use `==` and `<>` for equality and inequality, and `<`, `<=`, `>` and
`>=` for ordering. Put a function name in backticks to call it as an
infix operator, as in ``3 `elem` [1, 2, 3]``. Test a string against a
regular expression with `s =~ /pattern/`.

The factorials example uses `product([1..i])` to multiply the integers
from `1` to `i`. It returns the factorials of `1` to `10` as records, ending
with `(f = 3628800, i = 10)`. [Try factorials](../examples/factorial.links).

## Data and patterns

### Tuples, records, lists and variants

A tuple `(20, "start")` groups values that can have different types.
Read the first component with `pair.1`. A record `(x=20, y=22)` names
its fields. Read a field with `point.x`, or use a pattern to bind
several fields at once. This block returns `42`.

```links
{
  var point = (x=20, y=22);
  var (x=first, y=second) = point;
  first + second
}
```

Lists contain elements of one type. Use `[]` for the empty list, `::`
to prepend an element and `++` to join two lists. A range such as
`[1..4]` includes both endpoints. `[4..1]` is empty. The type of a list
of integers is `List Int`.

A variant constructor starts with a capital letter and can carry a
value. The prelude defines `Maybe(a)` for `Nothing` and `Just(a)`, and
`Either(a,b)` for `Left(a)` and `Right(b)`.

### Matching patterns

Patterns can occur in `var` bindings, function parameters and `switch`
cases. A `switch` takes the first matching case. Here `head :: _`
matches a non-empty list and `_` ignores the tail. The switch returns
`42`.

```links
switch (Just([42, 99])) {
  case Just(head :: _) -> head
  case _ -> 0
}
```

The pattern `Just(n) as value` binds both the payload `n` and the
whole variant `value`. A `var` or parameter pattern that fails to
match raises a runtime error.

### Extending and updating records

Use `(name="start" | point)` to add a field that is absent and
`(named with x=21)` to replace an existing field. Both produce a new
record. A pattern `(x=first, y=second | rest)` binds the remaining
fields to `rest`. This example returns `(43, "start")`.

```links
var point = (x=20, y=22);
var named = (name="start" | point);
var moved = (named with x=21);
{
  var (x=first, y=second | rest) = moved;
  (first + second, rest.name)
}
```

### List comprehensions

In `for (pattern <- xs) body`, the generator draws values from `xs`.
The body returns a list on each iteration and the comprehension
joins those lists. Use `where` to filter and `orderby` to sort. Here,
filtering by score and sorting the remaining names by score returns
`["Ali", "Kim"]`.

```links
for ((name, score) <- [("Kim", 8), ("Ali", 6), ("Jo", 2)])
  where (score >= 5)
  orderby (score)
  [name]
```

Multiple generators use commas. Each generator's source expression
uses the scope outside the comprehension. The body, filter and
sort keys can use the variables bound by every generator.

The list example uses `[]` and `x :: rest` cases to map and fold over
`[1, 2, 3]`. The result `([2, 3, 4], 123, 321, [1, 2, 3])` contains the
mapped list, the left and right folds, and the values collected by a handler.
[Try map and folds](../examples/met/fresco-effects/list-map-fold.links).

## Functions and types

### Function calls and recursion

Define a named function with `fun name(x, y) { body }` or write
`fun(x) { body }` for an anonymous function. Calls evaluate the
arguments before the body. Each parameter group takes a separate
call. Here `add(2)` returns a function that keeps the value `2` for
`x`, and `map` applies it to each list element to give `[12, 22]`.

```links
fun add(x)(y) { x + y }
map(add(2), [10, 20])
```

A named function can call itself. Put mutually recursive functions in
a `mutual` block so they can call one another. This program returns
`(120, true)`.

```links
fun factorial(n) {
  if (n <= 1) 1 else n * factorial(n - 1)
}

mutual {
  fun isEven(n) { if (n == 0) true else isOdd(n - 1) }
  fun isOdd(n) { if (n == 0) false else isEven(n - 1) }
}

(factorial(5), isEven(4))
```

### Signatures and polymorphism

SmallLinks infers most types. Write `sig f : T` before a function
definition to give it a signature. Use `e : T` to check an expression
against a type or `x : T` on a parameter to annotate it. A type alias
such as `typename Pair(a) = (a, a);` names a type. Use `Pair(Int)` for
a pair of integers.

| Function type | Arguments in each call |
| --- | --- |
| `() -> Int` | No arguments. |
| `(()) -> Int` | One unit argument. |
| `(Int, Bool) -> Int` | An integer and a Boolean in one call. |
| `((Int, Bool)) -> Int` | One tuple argument. |
| `Int -> Int -> Int` | One integer argument in each of two calls. |

A `forall a` quantifies the type variable `a`. Each call can use a
different type for `a`, so the two calls to `identity` return
`(42, true)`. The `[]` gives the function an empty effect context.
See [Modal effect types](#modal-effect-types).

```links
sig identity : forall a. [] (a -> a)
fun identity(x) { x }
(identity(42), identity(true))
```

A callback that must itself be polymorphic needs an expected type or an
annotation with `forall` inside the parameter type. Use `~identity` to
pass the function with its quantifiers and modalities intact. The
rank-two example calls a polymorphic argument at `Int` and `Bool` and
returns `(42, 42, (42, true), (), 42, (42, true))`.
[Try rank-two polymorphism](../examples/met/fresco-types/rank-two.links).

The value restriction allows generalisation of function literals and
other eligible values, including records built from eligible values.
A call can return a polymorphic value when its result type already
has a `forall`. A recursive function needs a signature to call itself
at different types or return a polymorphic result. The Church numerals
example names a polymorphic function type `Nat`, then adds two Church
numerals and converts the result to the integer `4`.
[Try Church numerals](../examples/church.links).

### Open rows and recursive types

Record and variant types describe their fields or constructors with
rows. The record type `(x:a | r)` requires a field `x` of type `a` and
allows extra fields described by the row variable `r`. A signature
binds a row variable with `forall r::Row`. The two calls below use
different field types and extra fields, and return `(1, "one")`.

```links
sig getX : forall a, r::Row. ((x:a | r)) -> a
fun getX(r) { r.x }

(getX((x=1, y=true)), getX((x="one", z=0)))
```

The closed variant type `(|Zero | One|)` has two alternatives. Use
`mu n. T` to describe a recursive type. In `mu n. (|Zero | Succ:n|)`,
the payload of `Succ` has the whole recursive type `n`.

## Modules and imports

Use `module Name { ... }` to group declarations. Qualify a function as
`Name.member` or a type as `Name.T`. Use `open Name;` to bring the
module's names into scope without a qualifier. The expression
`Double.apply(21)` below returns `42`.

```links
module Double {
  fun apply(n) { n * 2 }
}

Double.apply(21)
```

Use `import Name;` to load another file as a module. Lower-case the
first letter of `Name` and append `.links` to get the file name.
`open import Name;` loads the module and brings its members into
scope. Each external module is loaded once per run and dependencies
are initialised first. When an example is loaded, the playground
searches the bundled standard library first, then the example's
directory.

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

### Declaring and invoking operations

Declare related operations in an `effect` interface at file or module
scope. In `Choose : () => Bool`, the operation takes no arguments and
returns a `Bool`. Use `do Choose` to invoke it or `do Op(args)` to pass
arguments. Qualify an operation from another module as in
`do Effects.Ask`. An interface can take type parameters. For example,
`effect Reader(a::Abs) { Ask : () => a; }` gives `Ask` result type `Int`
in a `Reader(Int)` instance. Operation arguments and results must have
absolute types, which have the same meaning in every effect context.
The annotation `a::Abs` requires an absolute type argument.

An operation can quantify its own result type, as in
`Fail : forall a::Abs. () => a`. Each call fixes `a` independently.
The handler's clause must work for every such `a`.

### Deep and nested handlers

A handler installs an instance of each interface named by its operation
clauses. Supply a clause for every operation of each installed
interface. The computation inside `handle(...)` can use those
interfaces. An operation from another interface goes to an enclosing
handler. When several clauses handle one operation, the first matching
argument pattern wins.

In a deep handler, written `handle`, `k` resumes the computation with
the operation result and reinstalls the handler around it. You can
call `k` repeatedly. Here the two resumptions supply `true` and `false`
to `Choose` and the return clause `case n -> [n]` turns each result
into a list. The final result is `[1, 2]`.

```links
effect Choice { Choose : () => Bool; }

handle(if (do Choose) 1 else 2) {
  case <Choose => k> -> k(true) ++ k(false)
  case n -> [n]
}
```

A handler without a return clause returns values unchanged when its
computation completes. An operation clause can omit the resumption.
In the single-yield example, `case <Yield(n)> -> n` ends the handled
computation at its first `Yield` and returns `1`.
[Try single yield](../examples/met/fresco-effects/single-yield.links).

Operation and return clauses run in the enclosing context. In the
nested example below, `do Ask` in the `if` uses the inner `Reader(Bool)`.
`do Ask` in the inner operation clause uses the outer `Reader(Int)`.
The outer handler supplies `42`, so `do Ask == 42` passes `true` to
the inner resumption and the whole program returns `1`.

```links
effect Reader(a::Abs) { Ask : () => a; }

handle(
  handle(if (do Ask) 1 else 0) {
    case <Ask => k> -> k(do Ask == 42)
  }
) {
  case <Ask => k> -> k(42)
}
```

### Shallow handlers and handler state

A shallow handler, written `shallowhandle`, resumes outside the
handler. The state module uses recursive calls to install another
shallow handler around each resumption. See
[Modules and imports](#modules-and-imports).

A parameterised deep handler uses `handle(e)(state <- initial)`.
It evaluates `initial` in the enclosing context before starting `e`.
Each clause can read `state`, and each call to `k` supplies the
operation result followed by the next state. The handler below
initialises the state to `40`, adds `2` and returns `42`.

```links
effect State(a::Abs) {
  Get : () => a;
  Put : (a) => ();
}

handle({
  var n = do Get;
  do Put(n + 2);
  do Get
})(state <- 40) {
  case <Get => k> -> k(state, state)
  case <Put(n) => k> -> k((), n)
}
```

## Modal effect types

### Effect contexts and rows

An effect context lists the effect interface instances available at
a point in a program. A bare function type `A -> B` uses the current
context for the function body and for interpreting `A` and `B`. For
example, `(a -> b, List a) -> List b` describes a mapping function
whose callback shares its context. A modality is a prefix on a type
that sets or changes the context used to interpret that type.

The effect context is a scoped row. Two instances of the same
interface can coexist, ordered from newest to oldest. A row
`[Reader(Bool), Reader(Int)]` has a visible `Reader(Bool)`, so
`do Ask` uses that instance. The order of instances of different
interfaces does not affect the type. To call a function with an
absolute type, supply a context whose newest instances for each
required interface match the stated instances in order. For example,
`[Reader(Int)] (() -> Int)` can be called when `Reader(Int)` is the
visible `Reader`. Other interfaces and older `Reader` instances
can also be present. A newer `Reader(Bool)` hides `Reader(Int)`.

### Absolute types, extensions and masks

| Type | Context used to interpret the type after the prefix |
| --- | --- |
| `[] (A -> B)` | The empty context. |
| `[Reader(Int)] (() -> Int)` | The fixed context containing `Reader(Int)`. |
| `<Reader(Int)> (() -> Int)` | The current context with a new `Reader(Int)` instance. |
| `<Reader \|> (() -> Int)` | The current context with its newest `Reader` instance removed, if present. |
| `<Reader \| Reader(Bool)> (() -> Bool)` | The current context after removing the newest `Reader`, if present, then adding `Reader(Bool)`. |

Square brackets specify an absolute modality. A function with type
`[] (A -> B)` can be called from a larger context while its body is
checked in the empty one. Angle brackets specify a relative modality.
`<>` leaves the current context unchanged. Each interface name in
the mask removes one instance, so `<Reader, Reader |>` removes up
to two. Use parentheses to apply a modality to a whole arrow type.
Modalities can also appear inside data types, as in
`List ([] (Int -> Int))`.

A mask changes how a type is interpreted. Writing a mask does not
change which handler receives a `do` operation. The `hold` function
below carries `f` through a `Tick` handler. In the handled computation,
`<Tick |>` removes the new `Tick` instance from the context used to
interpret the type of `f`, recovering its binding context. When the
handler returns `f`, the addition and mask cancel, restoring `f`'s
original type. The final call returns `42`.

```links
effect Tick { Tick : () => (); }

sig hold : [] ((() -> Int) -> (() -> Int))
fun hold(f) {
  handle({ do Tick; (f : <Tick |> (() -> Int)) }) {
    case <Tick => k> -> k(())
  }
}

hold(fun() { 42 })()
```

### Inference and annotations

A global named function, including a function in a module, is checked
in the empty context by default and receives an outer `[]`. A local
function uses its surrounding context. A global function that handles
its own operations can use the default. To call an operation supplied
by the caller, give the global function an absolute context containing
the required interface. Here `ask` needs `Reader`, and its caller
installs a handler that supplies `42`.

```links
effect Reader { Ask : () => Int; }

sig ask : [Reader] (() -> Int)
fun ask() { do Ask }

handle(ask()) { case <Ask => k> -> k(42) }
```

Removing the `sig` leaves `Reader` unavailable in the body of `ask`.
The checker can infer type arguments for an available interface
instance. It cannot add an interface or infer an unknown row of effects.
To resolve an ambiguous interface argument, annotate the operation
signature in its clause, for example
`case <Ask => k> : (() => Int) -> k(42)` for `Reader(Int)`.

A binding retains the context where it was defined. For example, a
function literal bound by a top-level `var` uses the top-level context
by default. Give the literal a type such as `[] (() -> Int)` when a
pure global function needs to call it. The value restriction also
applies to introducing a modality. An expected modal type can change
the context used to check a function literal. A call or `do` expression
is checked in its current context and can return a value whose result
type already has a modality.

### Native permissions

Top-level expressions and global `var` initialisers have `wild`, the
permission for native effects such as printing, reading the current
time and generating random values. Write `[wild]` in the signature
of a global function that needs the permission. Only an absolute
context can name `wild`. User-defined handlers cannot supply it.
The following program prints `hello` and returns `()`.

```links
sig say : [wild] (String -> ())
fun say(s) { print(s) }

say("hello")
```

`show` and `parseDate` require `wild` because they can use the local
time zone. Use `showUTC(d)` to format a date in UTC in pure code.

### Passing callbacks to a handler

Use a relative callback type when a function installs a handler around
the callback's body. Here `withAsk` is checked in `[]`. Its parameter
has type `<Reader> (() -> Int)`, which makes `Ask` available while
checking the supplied function literal. `withAsk` installs a `Reader`
handler before it calls `action()`. The handler resumes with `42`, so
the call returns `43`.

```links
effect Reader { Ask : () => Int; }

sig withAsk : [] ((<Reader> (() -> Int)) -> Int)
fun withAsk(action) {
  handle(action()) { case <Ask => k> -> k(42) }
}

withAsk(fun() { do Ask + 1 })
```

A bare arrow in a callback parameter uses the enclosing function
type's context. Installing a handler changes that context. To call
the callback in the original context, a handler can invoke it inside
an operation clause. In the search example, the `Test` clause calls
the predicate in the enclosing context, so the predicate's `Yield`
operations reach the caller's handler. The program returns
`([1, 2, 3], Just(3), (Just(2), [1, 2]))`.
[Search with effectful callbacks](../examples/met/fresco-effects/find_mask_paper.links).

### Returning values from a handler

A returned function keeps its effect requirements. Creating a
function inside a handler does not capture the handler. Here
`delayed` has type `<Reader> (() -> Int)` and its call uses the second
handler, which supplies `42`.

```links
effect Reader { Ask : () => Int; }

var delayed = handle(fun() { do Ask }) {
  case <Ask => k> -> k(0)
};
handle(delayed()) { case <Ask => k> -> k(42) }
```

The same rule applies when a returned function is stored in a record
or list. The handler results example runs a delayed state update under
a second handler. It returns `(52, (42, true, "second"))`, with `52`
as the new state and the remaining values chosen by returned functions.
[Try handler results](../examples/met/thesis/handler_results.links).

### Extending a record with a modality

When you extend a record with a fixed context, its inherited fields
keep that context where they need it. New fields use the current
context. In this example, adding `n` preserves the `Reader`
requirement of `run`. The handler supplies `41` and the program
returns `42`.

```links
effect Reader { Ask : () => Int; }

var record = ((run=fun() { do Ask }) : [Reader] (run:() -> Int));
var extended = (n=1 | record);
var answer = handle(extended.run()) { case <Ask => k> -> k(41) };
answer + extended.n
```

In the list example, `[Gen] (List (() -> ()))` fixes the context of
the whole list. Its elements have bare arrows that use `Gen`. The
program calls the first function under a `Gen` handler to collect `[1]`.
[Try a list of effectful functions](../examples/met/fresco-effects/effectful-list.links).

## Linear types

Use `linfun` to create a linear function. Its type uses `-@`. A linear
local binding or parameter must be used once on each branch of its
scope. A linear function can capture a linear value. This block
returns `42`. A block that calls `next` twice or leaves it unused is
rejected.

```links
{
  var next = linfun(n) { n + 1 };
  next(41)
}
```

A list is linear if its elements are linear. Use a cons pattern to
take the head and tail together. Functions such as `hd`, `tl` and
`length` require unrestricted elements because they can discard part
or all of the list. A deep handler with linear state needs an explicit
return clause. Each operation and return clause must use the linear
state once on each branch.

The linear list example takes apart a recursive variant, consumes
each element by wrapping it in a new linear function and returns
`LinCons(fun, LinNil)`. [Try linear map](../examples/linearList.links).
