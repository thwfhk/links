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
| List `List Int` | `[]`, `[1, 2, 3]` | Prepend with `x :: xs` and join with `xs ++ ys`. All elements have the same type. An integer range such as `[1..4]` includes both endpoints. A descending range such as `[4..1]` is empty. |
| Record `(x:Int, ready:Bool)` | `(x=42, ready=true)` | Read field `x` with `r.x`. Add it with `(x=42 \| r)` when absent, or replace it with `(r with x=42)` when present. Both forms produce a new record. |
| Variant `(\|Nothing \| Just:Int\|)` | `Nothing`, `Just(42)` | A constructor starts with a capital letter. It may carry a payload, as in `Just(42)`. Use `switch` to match the constructor. |

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

SmallLinks infers ordinary types. Write a signature when a global
function needs effects supplied by its caller.

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

Use `Int -> Int` as shorthand for `(Int) -> Int`. Type annotations and
printed types use `List Int` for lists and `(| One | Many:Int |)` for variants.
`List` is a built-in type name.

## Advanced features

### Recursive types

- **Syntax.** Write `mu n. T` to define a recursive type. Within `T`,
  `n` refers to the whole type.
- **Example.** `Nat` is a variant with `Zero` and `Succ`. Each `Succ`
  contains another `Nat`. `toInt(Succ(Succ(Zero)))` returns `2`.

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
a type variable to primitive
types. In a row tail such as `(x:Int | r::Base)`, `r::Base` limits the
remaining fields to primitive types.

**Record example.** The two calls to `getX` use different types for
`x` and different extra fields. The result is `(1, "one")`.

```links
sig getX : ((x:a | r)) -> a
fun getX(r) { r.x }

(getX((x=1, y=true)), getX((x="one", z=0)))
```

**Variant example.** In `(|One | r|)`, `One` has no payload and `r`
allows other constructors such as `Many`. The result is `(true, false)`.

```links
sig isOne : ((|One | r|)) -> Bool
fun isOne(v) { switch (v) { case One -> true case _ -> false } }

(isOne(One), isOne(Many(3)))
```

### Polymorphism

Fresco uses annotations and expected types to check polymorphic
values and modal types. A higher-rank parameter needs a polymorphic
annotation or an expected type that supplies the quantifier.
A function call, operation or handler computation cannot introduce
quantifiers or a modality implicitly. Lambdas, literals and eligible
records, lists and conditionals can introduce them.

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

This returns `42`. Adding a second call to `f` in the block is a
type error.

### Effect contexts and modal types

An ambient effect context lists the available effect interfaces. A
bare arrow uses that context for the function body, arguments and
result. An absolute modality `[E] T` gives `T` a fixed context `E`.
A relative modality changes the current context.

| Type | Context for the body of the type |
| --- | --- |
| `A -> B` | The current context. |
| `[] (A -> B)` | The empty context. |
| `[Reader(Int)] (() -> Int)` | A context containing `Reader(Int)`. |
| `[wild] (String -> ())` | A context with permission for native effects. |
| `<Reader(Int)> (() -> Int)` | The current context with a new `Reader(Int)` instance. |
| `<Reader \|> (() -> Int)` | The current context with its newest `Reader` instance removed. |
| `<Reader \| Reader(Bool)> (() -> Bool)` | Remove the newest `Reader` instance, then add `Reader(Bool)`. |

Put parentheses around an arrow beneath a modality. Modalities can
also occur in data types, as in `List ([] (Int -> Int))`. A mask in
a type changes which context the value requires. It leaves handler
dispatch unchanged.

SmallLinks checks an unannotated global function in the empty context
and gives its type an outer `[]`. Local functions use their surrounding
context. The top-level expression and global `var` initialisers
have `wild`. Use `[wild]` in the signature of a function that prints,
reads the time or performs other native effects. Recursion, ranges
and algebraic handlers can run in the empty context.

Declare operations in an effect interface. Interface parameters fix
the types shared by its operations, and an operation's own quantifiers
are instantiated at each call. Operation arguments and results must
be absolute. Base types are absolute, data types are absolute when
their components are absolute, and an absolute modality gives a
function an absolute type. Use `a::Abs` to require an absolute type
argument.

```links
effect Reader(a::Abs) {
  Ask : () => a;
}

sig ask : [Reader(Int)] (() -> Int)
fun ask() { do Ask }

handle(ask()) { case <Ask => k> -> k(42) }
```

This returns `42`. Calling `ask()` needs an available `Reader(Int)`
instance. See the [modal effect types design](../met/SPEC.md)
for the inference rules and examples.

## Algebraic effects and handlers

Use `do Op(args)` to invoke a declared operation. An operation with no
arguments can be written `do Op`. Use a qualified name such as
`do Effects.Ask` when the operation belongs to a module. A call uses the
newest available instance of the interface that declares the operation.

A handler installs one instance of each interface it handles and
covers every operation of each installed interface. Operations from
other interfaces are forwarded. When a handler owns an operation and
all its argument patterns fail, evaluation raises a match error.
Operation and return clauses run in the enclosing context. The default
return clause returns the value and preserves any effects it requires.
An operation clause can bind a resumption `k`. Call `k` with the result
of the operation to continue the computation.
A clause may call `k` several times. A clause such as
`case <Stop> -> 0` discards the resumption.

```links
effect Choice { Choose : () => Bool; }

handle(if (do Choose) 1 else 2) {
  case <Choose => k> -> k(true) ++ k(false)
  case n -> [n]
}
```

This returns `[1, 2]`. In a deep handler, written `handle`, a
resumption reinstalls the handler and returns the handler's result.
In a shallow handler, written `shallowhandle`, a resumption continues
the computation and returns the computation's result. It requires a
new handler for the same interfaces.

```links
effect Counter { Next : () => Int; }

shallowhandle(do Next + do Next) {
  case <Next => k> ->
    handle(k(20)) { case <Next => next> -> next(22) }
}
```

This returns `42`.

A parameterised deep handler takes initial values after the computation.
The initial values must be absolute. Each call to `k` supplies the
operation result followed by the next values of the parameters.
Here `Get` returns the current state and `Put` changes it.

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

This returns `(Just(42), Nothing)`. See the
[handler examples](../../examples/handlers) for more programs.

## Other native features

- The compiler rejects [`escape` expressions](../met/SPEC.md#native-effects).
- Use `s =~ /pattern/` to test a string against a regular expression.
  For example, `"42" =~ /^[0-9]+$/` returns `true`. Use
  `s =~ s/pattern/replacement/` for replacement.
- Use `parseDate("2022-08-04 12:03:12")` to read a `DateTime` from a
  string, `intToDate(n)` to convert seconds since the Unix epoch, and
  `show(d)` to format a date.
