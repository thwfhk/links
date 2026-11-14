# SmallLinks language guide

SmallLinks is a call-by-value functional language with type and effect
inference. Programs run in a native interpreter. The [plan](PLAN.md#scope)
lists the boundaries of the subset.

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

## Basic features

A source file contains declarations and may end with an expression. A
`#` starts a comment that runs to the end of the line.

### Terms by type

| Type | Example values | Common terms |
| --- | --- | --- |
| `()` | `()` | Use the unit value when there is no other result to return. |
| `Bool` | `true`, `false` | Use `not(b)` for negation, `a && b` for and, and `a \|\| b` for or. The last two evaluate the right operand only when needed. In `if (b) yes else no`, `b` must be a `Bool`, both branches must have the same type, and only the chosen branch runs. |
| `Int` | `42`, `-3` | Use `+`, `-`, `*` and `/` for integer arithmetic. |
| `Float` | `3.5`, `-.0.5` | Use `+.`, `-.`, `*.` and `/.` for floating-point arithmetic. |
| `Char` | `'a'`, `'\n'` | Use `ord(c)` to get a character's integer code. |
| `String` | `"hello"`, `"line\n"` | Join strings with `s ^^ t`. |
| `DateTime` | `intToDate(0)`, `parseDate("2022-08-04 12:03:12")` | Format a date with `show(d)`. |
| Tuple `(Int, String)` | `(42, "hello")` | Read the first component with `pair.1`. Components can have different types. |
| List `[Int]` | `[]`, `[1, 2, 3]` | Prepend with `x :: xs` and join with `xs ++ ys`. All elements have the same type. An integer range such as `[1..4]` includes both endpoints. A descending range such as `[4..1]` is empty. |
| Record `(x:Int, ready:Bool)` | `(x=42, ready=true)` | Read field `x` with `r.x`. Add it with `(x=42 \| r)` when absent, or replace it with `(r with x=42)` when present. Both forms produce a new record. |
| Variant `[\|Nothing \| Just:Int\|]` | `Nothing`, `Just(42)` | A constructor starts with a capital letter. It may carry a payload, as in `Just(42)`. Use `switch` to match the constructor. |

### Bindings and blocks

Use `var name = expression;` to evaluate
an expression and bind its value. The binding lasts to the end of
the surrounding block or file. A new binding with the same name
shadows the earlier one. A block `{ ... }` evaluates its contents in
order and returns its final expression. An expression followed by a
semicolon in a block must have type `()`. End the block with `()`
when it should return unit.

### Patterns and `switch`

Use `var pattern = expression;` within a
block to take apart a value. Function parameters can also be
patterns. Evaluation raises a runtime error if a local binding or
parameter pattern fails to match. A `switch` uses the first matching
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

### Record patterns

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

### List comprehensions

In `for (pattern <- xs) body`, the
generator draws values from `xs`. The body returns a list for each
set of values drawn, and the comprehension joins these lists. Use
`where (condition)` to filter the results and `orderby (key)` to
sort them by a key of a base type such as `Int`, `String` or
`DateTime`. Separate multiple generators or sort keys with commas.
Each generator's source uses the scope outside the comprehension.
The body, filter and sort keys can use the names bound by all
generators.

```links
for ((name, score) <- [("Kim", 8), ("Ali", 6), ("Jo", 2)])
  where (score >= 5)
  orderby (score)
  [name]
```

This returns `["Ali", "Kim"]`. The prelude supplies list functions
such as `map`, `filter` and `fold_left`.

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

Declare an operator's precedence and associativity with `infix`,
`infixl` or `infixr`, or its position with `prefix` or `postfix`.
Define the operator with `op`. This example defines `!` as a
prefix operator and returns `true`.

```links
prefix 9 !;
op ! x { not(x) }

!false
```

### Modules and imports

Use `module Name { declarations }` to
group declarations in a file. Use a qualified name such as `Name.f`
or `Name.T` to refer to a function or a type. Use `open Name;` to
bring the module's names into scope without a qualifier.

Use `import Name;` to load another file as a module. For example,
`import Arithmetic;` loads declarations from `arithmetic.links`.
The file name starts with the lower-case form of the module name's
first letter. Use `--path=dir` to add a directory to the module
search path. The combined form `open import Name;` also opens the
module.

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

### Type annotations and aliases

SmallLinks infers types and effects. Use these forms to write types
explicitly.

| Form | Use |
| --- | --- |
| `sig name : T` | Give a function definition or a top-level `var` declaration a signature. |
| `e : T` | Check an expression against a type. |
| `x : T` | Annotate a parameter. |
| `typename Pair(a) = (a, a);` | Name a pair type. Use `Pair(Int)` for a pair of integers. |

In a function type, each arrow follows one group of arguments.

- `(Int, Bool) -> String` takes two arguments.
- `((Int, Bool)) -> String` takes one tuple argument.
- `(Int) -> (Int) -> Int` takes its arguments in two separate calls.

See [Effect annotation syntax](#effect-annotation-syntax) for function
types in aliases and explicit `forall` types.

## Advanced features

### Recursive types

- **Syntax.** Write `mu n. T` to define a recursive type. Within `T`,
  `n` refers to the whole type.
- **Example.** `Nat` is a variant with `Zero` and `Succ`. Each `Succ`
  contains another `Nat`. `toInt(Succ(Succ(Zero)))` returns `2`.

```links
typename Nat = mu n. [|Zero | Succ:n|];

fun toInt(n:Nat) {
  switch (n) {
    case Zero -> 0
    case Succ(previous) -> 1 + toInt(previous)
  }
}

toInt(Succ(Succ(Zero)))
```

### Rows

Rows describe record fields, variant alternatives and operations.

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
variable, `p::Presence` for a presence variable and `e::Eff` for an
effect row variable. `a::Base` limits a type variable to primitive
types. In a row tail such as `(x:Int | r::Base)`, `r::Base` limits the
remaining fields to primitive types.

**Record example.** The two calls to `getX` use different types for
`x` and different extra fields. The result is `(1, "one")`.

```links
sig getX : ((x:a | r)) -> a
fun getX(r) { r.x }

(getX((x=1, y=true)), getX((x="one", z=0)))
```

**Variant example.** In `[|One | r|]`, `One` has no payload and `r`
allows other constructors such as `Many`. The result is `(true, false)`.

```links
sig isOne : ([|One | r|]) -> Bool
fun isOne(v) { switch (v) { case One -> true case _ -> false } }

(isOne(One), isOne(Many(3)))
```

### FreezeML

An ordinary use of a polymorphic variable instantiates its type.

| Form | Use |
| --- | --- |
| `~ident` | Keep the quantified type of `ident`. |
| `$(e)` | Generalise the type of a value. |
| `e@` | Instantiate a polymorphic expression. |
| `/\ [a]. { e }` | Introduce a type variable explicitly. |
| `e[Int]` | Supply a type argument. |

**Passing a polymorphic function.** `poly` needs an argument it can
call at both `Int` and `Bool`. The result is `(42, true)`.

```links
sig ident : forall a,e::Row. (a) -e-> a
fun ident(x) { x }

fun poly(f : (forall a,e::Row. (a) -e-> a)) { (f(42), f(true)) }
poly(~ident)
```

**Supplying a type argument.** `keep` has a type parameter `a`. The
call supplies `Int` and returns `42`.

```links
var keep = /\ [a]. { fun(x:a) { x } : (a) {}~> a };
(~keep)[Int](42)
```

### Linear types

- Use `linfun` to create a linear function. Its type uses `-@` or `~@`.
- Use a linear local or parameter once on each branch of its scope.
- A linear closure can capture a linear value.

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
| `(A) {}~> B` | The row is closed and contains only `wild`. |

- **Sharing rows.** Each bare `->` introduces its own row. To share
  a tail, use the same named variable in each row and write the
  presence fields each row needs.
- **Row variables and alias arguments.** Supply all alias arguments,
  including row arguments. Aliases and explicit `forall` types
  require their row variables to be bound. In signatures with
  implicit quantification, `_` denotes a fresh rigid variable and
  `%` denotes a fresh flexible variable.
- **Matching effects at a call.** The top-level effect row is
  `{wild:()}`. A call matches the function's effect row against the
  current row. A function with a closed empty row needs an empty
  current row.
- **The `wild` effect.** Recursive calls, list ranges, handlers and
  functions such as `print` require `wild`. You can write `(A) ~> B`
  as `(A) {wild:() | _}-> B` and `(A) {}~> B` as `(A) {wild:()}-> B`.

**Effect aliases.** Use `effectname` to name an effect row. Write an
operation field as `Ask:() => a` or `Ask:a` for an operation with no
arguments. For an operation with arguments, list their types before
`=>`, as in `Put:(Int) => ()`. The example supplies an empty row
argument to `Reader`, adds `wild` with `~>` and returns `42`.

```links
effectname Reader(a,e::Eff) = {Ask:() => a | e};

sig ask : () { |Reader(Int,{})}~> Int
fun ask() { do Ask }

handle(ask()) { case <Ask => k> -> k(42) }
```

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
