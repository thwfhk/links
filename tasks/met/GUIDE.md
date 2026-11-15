# SmallLinks language guide

SmallLinks is a call-by-value functional language with type inference,
algebraic effects and a native interpreter. Each Links code block is
a complete program unless the text gives a file name.

- [Running programs](#running-programs)
- [Values and expressions](#values-and-expressions)
- [Modules and imports](#modules-and-imports)
- [Types and annotations](#types-and-annotations)
- [Effects and handlers](#effects-and-handlers)
- [Modal types and callbacks](#modal-types-and-callbacks)

## Running programs

Run these commands from the repository root. For an installed
interpreter, use `linx` in place of `./links`. See the
[installation instructions](../../INSTALL.md) for dependencies.

1. `make` builds SmallLinks and creates the `./links` launcher.
2. `./links examples/factorial.links` runs the factorial example.
3. `./links -e '6 * 7'` evaluates the expression and prints `42 : Int`.
4. `./links --set=typecheck_only=true examples/factorial.links` checks
   the factorial example without evaluating it.
5. `./links` starts the REPL. End each expression or function
   definition with a semicolon. Enter `fun double(x) { x * 2 };`
   and then `double(21);` to print `42 : Int`. Enter `@quit;` to exit.

### File and REPL scope

Each command-line file starts with the prelude by default. Use
`--set=isolation=false` to let later files use definitions from earlier
successful inputs. At the REPL, use `@load "file.links";` to run a file
and its imports as one input.

Calling `exit(v)` prints `v` and ends the current input. The interpreter
then runs the next file or returns to the prompt. The argument `v` must
be absolute and unrestricted, and the call requires `wild`. A runtime
error in a file stops the batch.

When `exit(v)` interrupts an input, or a REPL command raises an error,
the interpreter discards definitions from that input. Earlier
definitions remain in scope. Native effects that already ran, such as
printing, still take effect, and any earlier linear binding used
during the interrupted input is used up.

## Values and expressions

A source file contains declarations and may end with an expression. A
`#` starts a comment that runs to the end of the line.

### Literals and data

| Type | Example values | Common terms |
| --- | --- | --- |
| `()` | `()` | Use the unit value when there is no other result to return. |
| `Bool` | `true`, `false` | Use `not(b)` for negation, `a && b` for conjunction and `a \|\| b` for disjunction. The last two evaluate the right operand only when needed. In `if (b) yes else no`, `b` must be a `Bool`, both branches must agree on the result type, and only the chosen branch runs. |
| `Int` | `42`, `-3` | Use `+`, `-`, `*` and `/` for integer arithmetic. |
| `Float` | `3.5`, `-.0.5` | Use `+.`, `-.`, `*.` and `/.` for floating-point arithmetic. |
| `Char` | `'a'`, `'\n'` | Use `ord(c)` to get a character's integer code. |
| `String` | `"hello"`, `"line\n"` | Join strings with `s ^^ t`. |
| `DateTime` | `intToDate(0)`, `parseDate("2022-08-04 12:03:12")` | Format a date with `show(d)` or `showUTC(d)`. |
| Tuple `(Int, String)` | `(42, "hello")` | Read the first component with `pair.1`. Components can have different types. |
| List `List Int` | `[]`, `[1, 2, 3]` | Prepend with `x :: xs` and join with `xs ++ ys`. All elements have the same type. An integer range such as `[1..4]` includes both endpoints. A descending range such as `[4..1]` is empty. |
| Record `(x:Int, ready:Bool)` | `(x=42, ready=true)` | Read field `x` with `r.x`. Add it with `(x=42 \| r)` when absent, or replace it with `(r with x=42)` when present. Both forms produce a new record. |
| Variant `(\|Nothing \| Just:Int\|)` | `Nothing`, `Just(42)` | A constructor starts with a capital letter. It may carry a payload, as in `Just(42)`. Use `switch` to match the constructor. |

### Bindings and blocks

Use `var name = expression;` to evaluate an expression and bind its
value. The binding lasts to the end of the surrounding block or file.
A new binding with the same name shadows the earlier one. A block
`{ ... }` evaluates its contents in order and returns its final
expression. An expression followed by a semicolon in a block must
have type `()`. End the block with `()` when it should return unit.

### Patterns and `switch`

Use `var pattern = expression;` within a block to take apart a value.
Function parameters can also be patterns. Evaluation raises a
runtime error if a local binding or parameter pattern fails to
match. A `switch` uses the first matching
case. Patterns include variables, the wildcard `_`, literals, tuples,
records, lists and variants. In a list pattern `head :: tail`,
`head` matches the first element and `tail` matches the rest.
`Just(n) as value` binds the payload to `n` and the whole variant
to `value`.

```links
var input = Just((20, [22, 99]));
switch (input) {
  case Just((base, head :: _)) -> base + head
  case _ -> 0
}
```

This returns `42`. The prelude defines `Maybe(a)` for `Nothing`
and `Just(a)`, and `Either(a,b)` for `Left(a)` and `Right(b)`.

### Working with records

The pattern `(x=value | rest)` binds field `x`
to `value` and the remaining fields to `rest`.

```links
var point = (x=20, y=22);
var named = (name="start" | point);
var moved = (named with x=21);
{
  var (x=first, y=second | rest) = moved;
  (first + second, rest.name)
}
```

This returns `(43, "start")`.

A record update can name each field only once. When extending a
record whose type has a modality, inherited fields keep any effects
they need. See [Modal record extension](#modal-record-extension).

### List comprehensions

In `for (pattern <- xs) body`, the generator draws values from `xs`.
The body returns a list for each set of values drawn, and the
comprehension joins these lists. Use `where (condition)` to filter
the results and `orderby (key)` to
sort them by a key of a base type such as `Int`, `String` or
`DateTime`. Separate multiple generators or sort keys with commas.
Each generator's source uses the scope outside the comprehension.
The first source runs once. Each later source runs once for each
combination drawn from the preceding generators, and may run zero
times. Later sources cannot use linear bindings from outside the
comprehension. The body, filter and sort keys can use the names
bound by all generators.

```links
for ((name, score) <- [("Kim", 8), ("Ali", 6), ("Jo", 2)])
  where (score >= 5)
  orderby (score)
  [name]
```

This returns `["Ali", "Kim"]`. Comprehensions use bundled list helpers
and work with an empty or custom prelude. Explicit calls to `map` and
other list functions use the definitions in scope. Comprehensions
require unrestricted elements in the generator and result lists.

### Functions and recursion

Use `fun name(x, y) { body }` to define a
function and `name(1, 2)` to call it. A call evaluates its arguments
before running the function body. An anonymous function has the
form `fun(x) { body }`. A function can use names from the scope
where it was defined. Each group of parameters in a curried
definition takes a separate call.

```links
fun add(x)(y) { x + y }
var addTwo = add(2);
map(addTwo, [10, 20])
```

This returns `[12, 22]`. The function `addTwo` keeps the argument
`x` from `add(2)`.

A named function can call itself. Use `mutual` to let
several functions call one another.

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

This returns `(120, true)`.

### Comparisons and operators

Use `==` and `<>` for equality and
inequality, and `<`, `<=`, `>` and `>=` for ordering. Equality
works on lists, records and variants when their contents can be
compared. Comparing functions raises a runtime error. Put a function
name in backticks to call it as an infix operator, as in
``3 `elem` [1, 2, 3]``.

You can redefine a comparison with `op`. Its result must be `Bool`.
Infix calls use the argument types and effects of the definition in scope.

Declare an operator's precedence and associativity with `infix`,
`infixl` or `infixr`, or its position with `prefix` or `postfix`.
Define the operator with `op`. This example defines `!` as a
prefix operator and returns `true`.

```links
prefix 9 !;
op ! x { not(x) }

!false
```

### Regular expressions

Use `s =~ /pattern/` to test a string against a regular expression and
`s =~ s/pattern/replacement/` to replace a match. For example,
`"42" =~ /^[0-9]+$/` returns `true`.

## Modules and imports

Use `module Name { declarations }` to group declarations in a file.
Use a qualified name such as `Name.f`
or `Name.T` to refer to a function or a type. Use `open Name;` to
bring the module's names into scope without a qualifier.

Use `import Name;` to load another file as a module. For example,
`import Arithmetic;` loads declarations from `arithmetic.links`.
The file name starts with the lower-case form of the module name's
first letter. Use `--path=dir` to add a directory to the module
search path. The combined form `open import Name;` also opens the
module.

External modules loaded by imports are visible by name throughout the
input, including modules loaded through another module's imports. For
example, if `Arithmetic` imports `Constants`, you can use
`Constants.pi` after importing `Arithmetic`. `open Constants;` makes
its members available without the qualifier in the current scope.
Each external module is loaded once per input. Dependencies are
initialised first, with independent imports following written order.

Save these declarations as `arithmetic.links`.

```links
typename Number = Int;

sig double : (Number) -> Number
fun double(n) { n * 2 }
```

Save this program as `main.links` in the same directory. Run
`./links --path=dir dir/main.links` from the repository root, using
the directory containing the two files for `dir`.

```links
import Arithmetic;

var value = 21 : Arithmetic.Number;
Arithmetic.double(value)
```

The program returns `42`.

## Types and annotations

SmallLinks infers the types of ordinary functions and values. Add an
annotation to specify a type, a polymorphic parameter or an effect
context the checker cannot infer. Bind each new type, row or presence
variable in a signature with `forall`. Signatures and type aliases
reject anonymous `%` holes.

| Form | Use |
| --- | --- |
| `sig name : T` | Give a function definition or a top-level `var` declaration a signature. |
| `e : T` | Check an expression against a type. |
| `x : T` | Annotate a parameter. |
| `typename Pair(a) = (a, a);` | Name a pair type. Use `Pair(Int)` for a pair of integers. |

In a function type, each arrow follows one group of arguments.

- `() -> Int` takes no arguments. `(()) -> Int` takes one unit argument.
- `(Int, Bool) -> String` takes two arguments.
- `((Int, Bool)) -> String` takes one tuple argument.
- `(Int) -> (Int) -> Int` takes its arguments in two separate calls.

Use `Int -> Int` as shorthand for `(Int) -> Int`. The same shorthand
works with the linear arrow `-@`. Write `List Int` for a list of integers
and `List (List Int)` for a nested list. Parenthesise an element type that
is a list, arrow, modality, quantified type or recursive type. `List`
is a built-in type name. Write `(| One | Many:Int |)` for a variant type.

An upcast `e : B <- A` checks `e` at `A` and gives it type `B`.
Evaluation returns the original value. An upcast can add variant
alternatives or omit unrestricted record fields from the type.
It cannot discard linear fields or change a function's argument
count or linearity.

### Recursive types

Write `mu n. T` to define a recursive type. Within `T`, `n` refers to
the whole type. Unfolding must reach a data or function type before
repeating a recursive reference. `Nat` reaches a variant with `Zero`
and `Succ`. Each `Succ` contains another `Nat`.

```links
typename Nat = mu n. (|Zero | Succ:n|);

fun toInt(n:Nat) {
  switch (n) {
    case Zero -> 0
    case Succ(previous) -> 1 + toInt(previous)
  }
}

toInt(Succ(Succ(Zero)))
```

This returns `2`.

### Rows

Rows describe record fields and variant alternatives.

| Form | Meaning |
| --- | --- |
| `(x:a)` | The record has a closed row with field `x`. |
| `(x:a \| r)` | The record has an open row. The tail `r` can describe more fields. |
| `x:T` or `x{:T}` | The field `x` is present at type `T`. |
| `x-` or `x{-}` | The field `x` is absent. |
| `x{p}` | The variable `p` specifies whether `x` is absent or present with a type. |

Use `{x:Int}` to supply a row as a type argument, `{:Int}` to supply
a present field and `{-}` to supply an absent field.

In a quantifier, use `a::Type` for a type variable, `r::Row` for a row
variable and `p::Presence` for a presence variable. `a::Base` limits
a type variable to primitive types. In a row tail such as
`(x:Int | r::Base)`, `r::Base` limits the
remaining fields to primitive types.

**Record example.** The two calls to `getX` use different types for
`x` and different extra fields. The result is `(1, "one")`.

```links
sig getX : forall a, r::Row. ((x:a | r)) -> a
fun getX(r) { r.x }

(getX((x=1, y=true)), getX((x="one", z=0)))
```

**Variant example.** In `(|One | r|)`, `One` has no payload and `r`
allows other constructors such as `Many`. The result is `(true, false)`.

```links
sig isOne : forall r::Row. ((|One | r|)) -> Bool
fun isOne(v) { switch (v) { case One -> true case _ -> false } }

(isOne(One), isOne(Many(3)))
```

### Polymorphism

An inferred function such as `fun ident(x) { x }` can be called at
different types. A parameter that must itself be polymorphic needs an
annotation or an expected type with `forall`.

SmallLinks can generalise the types of functions, literals and
expressions such as records or lists built from eligible values.
This is the value restriction. It also controls which expressions
can implicitly acquire a modality from an expected type. Calls,
operation invocations and handler computations can return values
with polymorphic or modal types already in their result types.

| Form | Use |
| --- | --- |
| `~ident`, `~(e)` | Keep the quantifiers and modalities after checking access to the value. |
| `$(e)` | Generalise the type of a value. |
| `e@` | Instantiate a polymorphic expression. |
| `/\ [a]. { e }` | Introduce a type variable explicitly. |
| `e[Int]` | Supply a type argument. |

**Passing a polymorphic function.** `poly` needs an argument it can
call at both `Int` and `Bool`. The result is `(42, true)`.

```links
sig ident : forall a. [] (a -> a)
fun ident(x) { x }

fun poly(f : (forall a. [] (a -> a))) { (f(42), f(true)) }
poly(~ident)
```

**Supplying a type argument.** `keep` has a type parameter `a`. The
call supplies `Int` and returns `42`.

```links
var keep = /\ [a]. { fun(x:a) { x } : (a) -> a };
(~keep)[Int](42)
```

A function that calls itself at different types needs a signature.
A recursive function that returns a polymorphic value needs a signature
with a `forall` inside the result type. Here `g` can be called at
`Int` and `Bool` because `f` returns a polymorphic function.

```links
sig f : Int -> (forall a. a -> a)
fun f(n) { if (n == 0) fun(x) { x } else f(n - 1) }
var g = f(1);
(g(42), g(true))
```

This returns `(42, true)`.

### Linear types

- Use `linfun` to create a linear function. Its type uses `-@`.
- Use a linear local or parameter once on each branch of its scope.
- A linear closure can capture a linear value.
- The REPL tracks the use of a linear binding across sentences.

```links
{
  var f = linfun(x) { x + 1 };
  f(41)
}
```

This returns `42`. A block that calls `f` twice is rejected.

A list is linear if its elements are linear. List literals, `::` and
`++` can build such lists. Use a cons pattern to take the head and tail
together. Functions such as `hd`, `tl` and `length` require unrestricted
elements because they can discard part or all of the list.

## Effects and handlers

### Declaring and invoking operations

Declare related operations together in an effect interface at file or
module scope. Give each operation a signature `(P1, P2) => Q`, where
`P1` and `P2` are its argument types and `Q` is its result type.
Use `() => Q` for an operation with no arguments. Interface parameters
fix the types shared by its operations. In the example below,
`Reader(Int)` makes `Ask` return `Int`.

Call an operation with `do Op(args)` or use `do Op` for an operation
with no arguments. The call uses the newest available instance of the
interface declaring `Op`. Qualify names across modules as needed,
for example `Effects.Reader(Int)` in a type and `do Effects.Ask`
in an expression. The type printer marks an interface as out of
scope if its original declaration has no name in the current scope.

```links
effect Reader(a::Abs) {
  Ask : () => a;
}

sig ask : [Reader(Int)] (() -> Int)
fun ask() { do Ask }

handle(ask()) { case <Ask => k> -> k(42) }
```

This returns `42`. The handler makes `Reader(Int)` available during
`ask()`. Its clause resumes the computation with `42` as the result
of `Ask`. The function signature supplies that context for the body
of `ask`. See [Effect contexts](#effect-contexts).

Operation arguments and results must have absolute types. An absolute
type has the same meaning in every effect context. Base types are
absolute, data types are absolute when their components are absolute,
and a function type with a fixed context such as `[](Int -> Int)`
is absolute. Use `a::Abs` for an absolute type argument or
`a::MonoAbs` for an absolute monotype. An operation signature can
refer to its own interface and to earlier interfaces in scope.

### Deep handlers

A handler installs an instance of each interface named by its operation
clauses. Provide a clause for every operation of each installed
interface. If several clauses match the same operation, the first
matching argument pattern wins. Evaluation raises a match error if all
its patterns fail. Operations from other interfaces go to enclosing
handlers.

The handled computation runs with the new interfaces available.
The operation and return clauses run in the enclosing context. For
example, if an inner clause invokes `Ask` while an outer `Reader`
handler is active, that call uses the outer instance.

In a deep handler, written `handle`, the resumption `k` reinstalls
the handler and returns the handler's result. Call `k` with the
result of the operation to continue the computation. A clause can
call `k` more than once or omit it, as in `case <Stop> -> 0`. A
return clause such as `case n -> [n]` runs when the handled
computation returns a value.
The default return clause returns that value and preserves any effects
it requires. Deep handler clauses can capture unrestricted bindings
from the enclosing context. Use a state parameter to pass a linear
value to a deep handler's clauses.

```links
effect Choice { Choose : () => Bool; }

handle(if (do Choose) 1 else 2) {
  case <Choose => k> -> k(true) ++ k(false)
  case n -> [n]
}
```

This returns `[1, 2]`.

For an interface with parameters, all its clauses agree on the same
type arguments. If inference leaves a choice, add an annotation. For
example, `case <Ask => k> : (() => Int) -> k(42)` fixes the result
of `Ask` and therefore the type argument of `Reader`.

The following program is rejected. Its handler has a clause for
`Get` and also needs a clause for `Put`.

```links
effect State(a::Abs) {
  Get : () => a;
  Put : (a) => ();
}

handle(do Get) { case <Get => k> -> k(42) }
```

### Nested handlers

Nested handlers can install instances of the same interface with
different type arguments. In this example, the inner computation
uses `Reader(Bool)`. Its clause runs with `Reader(Int)` and passes
the result of `do Ask == 42` to the resumption.

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

This returns `1`.

### Shallow handlers

In a shallow handler, written `shallowhandle`, a resumption returns
the result of the handled computation. It continues outside the
shallow handler, so enclose the resumption call in a handler for the
same interfaces. If a shallow clause uses a captured linear value,
every clause must use it once on each branch.

```links
effect Counter { Next : () => Int; }

shallowhandle(do Next + do Next) {
  case <Next => k> ->
    handle(k(20)) { case <Next => next> -> next(22) }
}
```

This returns `42`.

### Parameterised handlers

Write a parameterised deep handler as `handle(e)(state <- initial)`
followed by its clauses. Write multiple state bindings separated by
commas. The initial values must be absolute. They run before the
handled computation, from left to right in the enclosing context.
Each call to `k` supplies the operation result followed by the next
values of the parameters. Each clause must use a linear state binding
once on each branch. A handler with linear state needs an explicit
return clause. Here `Get` returns the current state and `Put` changes
it.

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

This returns `42`.

### Polymorphic operations

An operation can have a polymorphic signature. In this example,
`Fail` can return any absolute type `a`, so `pick` can use it at both `Bool`
and `Int`. The handler turns failure into `Nothing`.

```links
effect Failure { Fail : forall a::Abs. () => a; }

sig attempt : forall b::Abs. (<Failure> (() -> b)) -> Maybe(b)
fun attempt(action) {
  handle(action()) {
    case <Fail> -> Nothing
    case value -> Just(value)
  }
}

sig pick : [Failure] (() -> Int)
fun pick() { if (do Fail) 42 else do Fail }

(attempt(fun() { 42 }), attempt(fun() { pick() }))
```

This returns `(Just(42), Nothing)`. Each `do Fail` instantiates the
operation's own `forall a`. The handler must work for any such `a`,
so its `Fail` clause discards the resumption and returns `Nothing`.

## Modal types and callbacks

### Effect contexts

The effect context describes the interfaces and native permissions
available at a point in the program. A bare function arrow uses
the current context for the function body, arguments and result.
An absolute modality `[E] T` fixes the context for `T` at `E`. A
relative modality extends or masks the current context. To call a
function with a modal type, the call site must supply the context
required by that type.

| Type | Context for the body of the type |
| --- | --- |
| `A -> B` | The current context. |
| `[] (A -> B)` | The empty context. |
| `[Reader(Int)] (() -> Int)` | A context containing `Reader(Int)`. |
| `[wild] (String -> ())` | A context with permission for native effects. |
| `<Reader(Int)> (() -> Int)` | The current context extended with a new `Reader(Int)` instance. |
| `<Reader \|> (() -> Int)` | The current context with its newest `Reader` instance removed. |
| `<Reader \| Reader(Bool)> (() -> Bool)` | Remove the newest `Reader` instance, then add `Reader(Bool)`. |

Put parentheses around the whole arrow type beneath a modality.
Modalities can also occur in data types, as in `List ([] (Int -> Int))`.
A mask such as `<Reader |>` changes the context used in a type.
A call to `do Ask` still selects the newest available `Reader`
instance.

In this example, `hold` carries its callback through a `Tick` handler.
The mask describes the callback's type inside the handled computation.
Returning the callback restores its original type.

```links
effect Tick { Tick : () => (); }

sig hold : []((() -> Int) -> (() -> Int))
fun hold(f) {
  handle({ do Tick; (f : <Tick |> (() -> Int)) }) {
    case <Tick => k> -> k(())
  }
}

hold(fun() { 42 })()
```

This returns `42`.

### When to add an effect annotation

SmallLinks checks a global named function in the empty context by
default and gives its type an outer `[]`. Local functions use their
surrounding context. Give a global function a signature with an
absolute context when it needs an operation from its caller. A
function that handles its own operations can be inferred in the
empty context.

The following program is rejected because `ask` is checked in the
empty context and `Ask` needs `Reader`. Add
`sig ask : [Reader] (() -> Int)` before the function definition to
supply that context.

```links
effect Reader {
  Ask : () => Int;
}

fun ask() { do Ask }

handle(ask()) { case <Ask => k> -> k(42) }
```

Use a parameter or result annotation when the checker needs more
information to choose between modal types or fix an interface's type
arguments. A binding keeps the effect context in which it was defined.
For example, a function literal bound to a top-level `var` uses the
top-level context by default. Annotate it with `[]` if a pure global
function needs to call it.

### Native effects

Top-level expressions and global `var` initialisers have `wild`.
Printing, reading the current time, generating random values and
socket I/O require it. Both `show` and `parseDate` require `wild`
because they can use the local time zone. Use `showUTC(d)` to
format a date in UTC in pure code. User-defined handlers cannot
supply `wild`. Recursion, ranges and installing handlers can run
in the empty context.

```links
sig say : [wild] (String -> ())
fun say(s) { print(s) }

say("hello")
```

This prints `hello` and returns `()`.

### Passing callbacks to a handler

A bare arrow lets a callback share the context of the function that
calls it. When the function installs a handler around the callback's
body, give the callback a relative type to describe the added
interface. In this example, `<Reader(Int)>` makes `Ask` available
while checking the callback.

```links
effect Reader(a::Abs) {
  Ask : () => a;
}

sig withAsk : forall a::Abs. []((<Reader(Int)> (() -> a)) -> a)
fun withAsk(action) {
  handle(action()) { case <Ask => k> -> k(42) }
}

withAsk(fun() { do Ask + 1 })
```

This returns `43`. A lambda passed to a parameter of type
`[] (() -> Int)` is checked in the empty context.

A handler clause runs in the enclosing context. A search can use a
`Test` operation to evaluate its predicate there and keep its own
`Yield` calls in the handled computation. See the
[search example](../../examples/met/fresco-effects/find_mask_paper.links).

### Returning values from a handler

When a handler returns a function unchanged, its type keeps any
dependency on the handler's interfaces. In this example, `delayed`
requires a new `Reader` handler when called.

```links
effect Reader { Ask : () => Int; }

var delayed = handle(fun() { do Ask }) {
  case <Ask => k> -> k(42)
};
handle(delayed()) { case <Ask => k> -> k(42) }
```

This returns `42`. The type of `delayed` is
`<Reader> (() -> Int)`. A function stored in a returned record
also keeps its effect requirement.

### Modal record extension

When extending a record with a fixed context, its inherited fields
keep that context where they need it. New fields use the current
context. In this example, adding `n` preserves the type of the
`run` callback.

```links
effect Reader { Ask : () => Int; }

var record = ((run=fun() { do Ask }) : [Reader] (run:() -> Int));
var extended = (n=1 | record);
var answer = handle(extended.run()) { case <Ask => k> -> k(41) };
answer + extended.n
```

This returns `42`. When extending a record outside its fixed context,
an unknown row tail must have kind `Row(Abs)`. An unknown field
presence must have kind `Presence(Abs)`. Instantiate a polymorphic
record before extending a field with unknown presence.

## More examples and library definitions

- [Example programs](../../examples)
- [Handler examples](../../examples/handlers)
- [Modal effect and Fresco examples](../../examples/met/README.md)
- [Prelude](../../prelude.links)
- [Importable standard library modules](../../lib/stdlib)
- [Modal effect types specification](SPEC.md)
