# SmallLinks language guide

SmallLinks is a call-by-value functional language with type and effect
inference. Programs run in a native interpreter. The [plan](PLAN.md#scope)
lists the boundaries of the subset.

## Running programs

Run `make` from the repository root to build SmallLinks and create
the `./links` launcher. Use `linx` when running the installed
interpreter. See the [installation instructions](../../INSTALL.md)
for dependencies and installation commands.

```sh
./links main.links
./links -e '6 * 7'
./links --set=typecheck_only=true main.links
./links
```

The first command runs a source file. The second evaluates an expression
and prints `42 : Int`. The third checks a file without evaluating it.
The fourth starts the REPL. End expressions and function definitions
in the REPL with a semicolon. For example, enter
`fun double(x) { x * 2 };` and then `double(21);`. Enter `@quit;` to
exit.

## Values and expressions

A source file contains declarations and may end with an expression. A
`#` starts a comment that runs to the end of the line.

| Type | Example values |
| --- | --- |
| `()` | `()`, the unit value |
| `Bool` | `true`, `false` |
| `Int` | `42`, `-3` |
| `Float` | `3.5`, `-.0.5` |
| `Char` | `'a'`, `'\n'` |
| `String` | `"hello"`, `"line\n"` |
| `DateTime` | `intToDate(0)`, `parseDate("2022-08-04 12:03:12")` |
| `(Int, String)` | `(42, "hello")` |
| `[Int]` | `[]`, `[1, 2, 3]` |
| `(x:Int, ready:Bool)` | `(x=42, ready=true)` |
| `[\|Nothing \| Just:Int\|]` | `Nothing`, `Just(42)` |

Tuple components can have different types. Use `pair.1` to read the
first component. All elements of a list have the same type.

Use `+`, `-`, `*` and `/` for integer arithmetic, and `+.`, `-.`,
`*.` and `/.` for floating-point arithmetic. Use `==` and `<>` for
equality and inequality, and `<`, `<=`, `>` and `>=` for ordering.
Equality works on lists, records and variants when their contents can
be compared. Comparing functions raises a runtime error.
Use `not(x)` for Boolean negation. The operators `&&` and `||`
evaluate their right operand only when needed. Use `^^` to join
strings and `++` to join lists. Put a function name in backticks to
call it as an infix operator, as in ``3 `elem` [1, 2, 3]``.

An expression `if (condition) yes else no` evaluates `yes` when the
condition is true and `no` when it is false. The condition has type
`Bool` and both branches have the same type.

### Bindings and patterns

Use `var name = expression;` to evaluate an expression and bind its
value. Bindings are in scope from their declaration to the end of the
surrounding block or file. A new binding with the same name shadows
the earlier one. A block evaluates its bindings and expressions in
order, then returns its final expression. An expression followed by a
semicolon in a block must have type `()`. Write `()` at the end when
the block should return unit.

Within a block, `var pattern = expression;` can take apart a value.
Function parameters can also be patterns. Use `switch` to choose a
branch by matching a value against patterns in order. Patterns include
variables, the wildcard `_`, literals, tuples, records, lists and
variants. In a list pattern `head :: tail`, `head` matches the first
element and `tail` matches the rest. The pattern `Just(n) as value`
binds the payload to `n` and the whole variant to `value`. A local
binding or function parameter with a pattern that fails to match raises
a runtime error.

```links
var input = Just((20, [22, 99]));
switch (input) {
  case Just((base, head :: _)) -> base + head
  case _ -> 0
}
```

This returns `42`. A variant constructor starts with a capital letter.
It can have a payload, as in `Just(42)`, or stand on its own, as in
`Nothing`. The prelude defines the aliases `Maybe(a)` for `Nothing`
and `Just(a)`, and `Either(a,b)` for `Left(a)` and `Right(b)`.

### Records and lists

Use `r.x` to read field `x`. The expression `(x=42 | r)` adds a new
field to a record that lacks `x`. The expression `(r with x=42)`
replaces an existing field. Both produce a new record. A record pattern
`(x=value | rest)` binds field `x` to `value` and the remaining fields
to `rest`.

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

The expression `x :: xs` adds `x` to the front of `xs`. An integer
range such as `[1..4]` includes both endpoints. A range with a lower
end value, such as `[4..1]`, is empty. The prelude supplies list
functions such as `map`, `filter` and `fold_left`.

In `for (pattern <- xs) body`, the generator draws values from `xs`.
The body returns a list for each set of values drawn, and the
comprehension concatenates these lists. Use `where (condition)` to
choose which results to keep and `orderby (key)` to sort them by a
key of a base type such as `Int`, `String` or `DateTime`. Separate
multiple generators or sort keys with commas. Each generator's source
uses the scope outside the comprehension. The body, filter and sort
keys can use the names bound by all generators.

```links
for ((name, score) <- [("Kim", 8), ("Ali", 6), ("Jo", 2)])
  where (score >= 5)
  orderby (score)
  [name]
```

This returns `["Ali", "Kim"]`.

### Functions and recursion

Use `fun name(x, y) { body }` to define a function and `name(1, 2)` to
call it. A call evaluates its arguments before running the function
body. An anonymous function has the form `fun(x) { body }`. A function
can use names from the scope where it was defined. Each group of
parameters in a curried definition takes a separate call.

```links
fun add(x)(y) { x + y }
var addTwo = add(2);
map(addTwo, [10, 20])
```

This returns `[12, 22]`. The function `addTwo` keeps the argument
`x` from `add(2)`.

A named function can call itself. Use `mutual` to let several functions
call one another.

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

Declare an operator's precedence and associativity with `infix`,
`infixl` or `infixr`, or its position with `prefix` or `postfix`.
Define the operator with `op`. For example, `!` can be an ordinary
prefix operator.

```links
prefix 9 !;
op ! x { not(x) }

!false
```

### Modules

Use `module Name { declarations }` to group declarations in a file.
Names can be qualified, as in `Name.f` for a function or `Name.T` for
a type. Use `open Name;` to bring names from the module into scope
without a qualifier.

To use another file as a module, write `import Name;`. For example,
`import Arithmetic;` loads declarations from `arithmetic.links`.
The file name starts with the lower-case form of the module name's
first letter. Use `--path=dir` to add a directory to the module search
path. The combined form `open import Name;` also opens the module.

Save these declarations as `arithmetic.links`.

```links
typename Number = Int;

sig double : (Number) -> Number
fun double(n) { n * 2 }
```

Save this program as `main.links` in the same directory and run
`./links --path=dir dir/main.links` from the repository root, using
the directory containing the two files for `dir`.

```links
import Arithmetic;

var value = 21 : Arithmetic.Number;
Arithmetic.double(value)
```

The program returns `42`.

## Types and inference

SmallLinks infers types and effects. Use `sig name : T` before a
function definition or a top-level `var` declaration to give it a
signature. Use `e : T` to check the type of an expression or
`x : T` to annotate a parameter. Declare an alias with `typename`.
For example, `typename Pair(a) = (a, a);` names a pair type, and
`Pair(Int)` uses the alias at `Int`.

The type `(Int, Bool) -> String` takes two arguments. The type
`((Int, Bool)) -> String` takes one tuple argument. Curried types have
an arrow for each argument group, as in `(Int) -> (Int) -> Int`.

A generalised binding can be used at different types. For example,
`fun same(x) { x }` can be called as both `same(1)` and `same(true)`.
The value restriction limits which expressions can be generalised. A
function definition can be generalised. A `var` binding whose
right-hand side is a function call gains no new type quantifiers.
A function that calls itself at different types needs a polymorphic
signature. Write `forall` to specify which variables a type quantifies
over.

Use `mu` to write a recursive type. In `mu n. [|Zero | Succ:n|]`,
`n` refers to the whole variant type, so `Succ` contains another
value of that type.

```links
typename Nat = mu n. [|Zero | Succ:n|];

sig toInt : (Nat) ~> Int
fun toInt(n) {
  switch (n) {
    case Zero -> 0
    case Succ(previous) -> 1 + toInt(previous)
  }
}

toInt(Succ(Succ(Zero)))
```

This returns `2`.

### Rows

Rows describe record fields, variant alternatives and operations. A
row with no tail is closed. A row can end in a variable after `|`,
such as `r` in `(x:a | r)`. Write `x:T` or `x{:T}` for a field
present at type `T`, and `x-` or `x{-}` for an absent field. In
`x{p}`, the presence variable `p` specifies whether `x` is absent or
present with a type. Quantification can range over types, rows and
field presence. In explicit type arguments, `{x:Int}` is a row,
`{:Int}` is a present field and `{-}` is an absent field.

Use `a::Type`, `r::Row` and `p::Presence` to declare the kind of a
quantified variable. `e::Eff` declares an effect row. A restriction
such as `a::Base` limits a type variable to primitive types. For a
row tail, `r::Base` limits its fields to primitive types.

```links
sig getX : ((x:a | r)) -> a
fun getX(r) { r.x }

(getX((x=1, y=true)), getX((x="one", z=0)))
```

This returns `(1, "one")`. The two calls use different types for
`x` and different extra fields. With variants, a row tail allows
alternatives beyond the named ones.

```links
sig isOne : ([|One | r|]) -> Bool
fun isOne(v) { switch (v) { case One -> true case _ -> false } }

(isOne(One), isOne(Many(3)))
```

This returns `(true, false)`. In `[|One | r|]`, `One` has no payload
and `r` allows other constructors such as `Many`.

### FreezeML and linear functions

An ordinary use of a polymorphic variable instantiates its type. A
frozen use, such as `~ident`, keeps its quantified type. Here, `poly`
needs an argument it can call at both `Int` and `Bool`.

```links
sig ident : forall a,e::Row. (a) -e-> a
fun ident(x) { x }

fun poly(f : (forall a,e::Row. (a) -e-> a)) { (f(42), f(true)) }
poly(~ident)
```

This returns `(42, true)`. Use `$(e)` to generalise a value and
`e@` to instantiate a polymorphic expression. Use `/\ [a]. { e }`
to introduce a type variable explicitly and `e[Int]` to supply a type
argument.

```links
var keep = /\ [a]. { fun(x:a) { x } : (a) {}~> a };
(~keep)[Int](42)
```

`linfun` creates a linear function. Its type uses the `-@` or `~@`
arrow. A linear local or parameter must be used once on each branch of
its scope. A linear closure can capture a linear value.

```links
{
  var f = linfun(x) { x + 1 };
  f(41)
}
```

This returns `42`. Adding a second call to `f` in the block is a
type error.

### Effect annotation syntax

An arrow records the effects a function can perform when called. In
these forms, `A` and `B` stand for value types and `e` stands for a
row variable.

| Form | Meaning |
| --- | --- |
| `(A) -> B` | The arrow introduces a fresh open effect row. |
| `(A) {}-> B` | The effect row is closed and empty. |
| `(A) {Ask:() => Int \| e}-> B` | The row contains `Ask`, which takes no arguments and returns `Int`, and has tail `e`. |
| `(A) -e-> B` | The effect row is `e`. This abbreviates `(A) {\|e}-> B`. |
| `(A) ~> B` | The fresh effect row contains `wild`. |
| `(A) ~e~> B` | The effect row extends `e` with `wild`. |

Each bare `->` introduces its own row. To share a tail between rows,
use the same named variable in each row and write the presence fields
each row needs. Supply all alias arguments, including row arguments.
Aliases and explicit `forall` types require their row variables to be
bound. In signatures with implicit quantification, `_` denotes a
fresh rigid variable and `%` denotes a fresh flexible variable.

`wild` is required by recursive calls, list ranges, handlers and
functions such as `print`.
The top-level effect row is `{wild:()}`. A call matches the
function's effect row against the current effect row, so a call to
a function with a closed empty row needs an empty current row.
`(A) ~> B` can also be written `(A) {wild:() | _}-> B`. The `_`
introduces a fresh row tail. `(A) {}~> B` has a closed row containing
only `wild` and can be written `(A) {wild:()}-> B`.

Use `effectname` to name an effect row. The following signature supplies
an explicit empty row argument to `Reader`. The operation field
`Ask:() => a` can also be written `Ask:a`. An operation with
arguments lists their types before `=>`, as in `Put:(Int) => ()`.

```links
effectname Reader(a,e::Eff) = {Ask:() => a | e};

sig ask : () { |Reader(Int,{})}~> Int
fun ask() { do Ask }

handle(ask()) { case <Ask => k> -> k(42) }
```

This returns `42`. The `~>` arrow adds `wild` to the row named by
`Reader(Int,{})`.

## Algebraic effects and handlers

Use `do Op(args)` to invoke an operation. An operation with no
arguments can be written `do Op`. The operation label starts with a
capital letter and is unqualified. The effect row of the computation
must admit the operation.

A handler has clauses for operation calls and for the value returned
by its computation. If there is no return clause, the handler returns
the value unchanged. The handler forwards an operation if it has no
clause for the operation's label. If it has clauses for the label and
all their argument patterns fail, evaluation raises a match error.
Operations in a handler's clause run in the enclosing context.
An operation clause can bind a resumption `k`. Call `k` with the result
of the operation to continue the computation.
A clause may call `k` several times. A clause such as
`case <Stop> -> 0` discards the resumption.

```links
handle(if (do Choose) 1 else 2) {
  case <Choose => k> -> k(true) ++ k(false)
  case n -> [n]
}
```

This returns `[1, 2]`. In a deep handler, written `handle`, a
resumption reinstalls the handler and has the handler's result type
and output effects. In a shallow handler, written `shallowhandle`,
the resumption continues the computation without reinstalling the
handler and has the input computation's result type and effects.
Here the shallow handler supplies `20` for the first `Next` and
the enclosing handler supplies `22` for the second. The result
is `42`.

```links
handle(
  shallowhandle(do Next + do Next) {
    case <Next => k> -> k(20)
  }
) {
  case <Next => k> -> k(22)
}
```

A parameterised deep handler takes initial values after the computation.
Each call to `k` supplies the operation result followed by the next
values of the parameters. Here `Get` returns the current state and
`Put` changes it.

```links
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

An operation can have a polymorphic signature. In this example,
`Fail` can return any type `a`, so `pick` can use it at both `Bool`
and `Int`. The handler turns failure into `Nothing`.

```links
sig attempt : (() {Fail:forall a. () => a | e}~> b) {Fail{_} | e}~> Maybe(b)
fun attempt(action) {
  handle(action()) {
    case <Fail> : (forall a. () => a) -> Nothing
    case value -> Just(value)
  }
}

sig pick : () {Fail:forall a. () => a}~> Int
fun pick() { if (do Fail) 42 else do Fail }

(attempt(fun() { 42 }), attempt(pick))
```

This returns `(Just(42), Nothing)`. See the
[handler examples](../../examples/handlers) for more programs.

## Other native features

- Use `escape done in e` to bind `done` within `e`. Calling
  `done(value)` returns `value` from the escape. For example,
  `escape done in { 1 + done(42) }` returns `42`.
- Use `s =~ /pattern/` to test a string against a regular expression.
  For example, `"42" =~ /^[0-9]+$/` returns `true`. Use
  `s =~ s/pattern/replacement/` for replacement.
- Use `parseDate("2022-08-04 12:03:12")` to read a `DateTime` from a
  string, `intToDate(n)` to convert seconds since the Unix epoch, and
  `show(d)` to format a date.
