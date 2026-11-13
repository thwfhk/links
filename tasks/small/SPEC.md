# SmallLinks language draft

SmallLinks is a call-by-value functional language with row-based type
and effect inference. Programs run in a native interpreter. The
[plan](PLAN.md#scope) lists the boundaries of the subset. Modal effect
types are outside this draft.

## Terms and values

A source file contains declarations and may end with an expression.
`var` binds a value or matches it against a pattern. Blocks introduce
lexical scope and evaluate bindings in order. Functions may be named or
anonymous, take several arguments, and be curried. Named functions can
call themselves; `mutual` groups mutually recursive declarations.

Values include unit `()`, booleans, integers, floats, characters,
strings, lists, tuples, records, variants and functions. `if` evaluates
one branch after checking its condition. `switch` tries patterns in
order. Patterns include variables, wildcards, literals, tuples, lists,
records and variant constructors. Records support field projection,
extension and update. List comprehensions support `where` and `orderby`.

Programs can import or open modules and use qualified names for terms
and types. The prelude provides common functions and aliases, including
`map`, `Maybe` and `Either`. Operation labels are unqualified.

## Types and inference

The compiler infers types and effects. `sig` gives a binding a
signature, and `e : T` checks an expression against `T`. `typename`
names a type and `effectname` names an effect row. SmallLinks keeps
Links let polymorphism, its value restriction, recursive types and
explicit `forall` in types. Polymorphic recursion requires a signature.

Rows describe record fields, variant alternatives or operations. A row
with no tail is closed. A row can end in a variable after `|`, such as
`r` in `(x:a | r)`. Write `x:T` or `x{:T}` for a field present at type
`T`, and `x-` or `x{-}` for an absent field. In `x{p}`, the presence
variable `p` specifies whether `x` is absent or present with a type.
Quantification can range over types, rows and field presence.

```links
sig getX : ((x:a | r)) -> a
fun getX(r) { r.x }

(getX((x=1, y=true)), getX((x="one", z=0)))
```

This returns `(1, "one")`. The two calls use different types for
`x` and different extra fields. With variants, the row tail allows
alternatives beyond the named ones:

```links
sig isOne : ([|One | r|]) -> Bool
fun isOne(v) { switch(v) { case One -> true case _ -> false } }

(isOne(One), isOne(Many(3)))
```

This returns `(true, false)`. In `[|One | r|]`, `One` has no payload;
`r` allows other constructors such as `Many`.

### FreezeML and linear functions

An ordinary use of a polymorphic variable instantiates its type. A
frozen use, such as `~ident`, keeps its quantified type.
Here, `poly` needs one argument it can call at both `Int` and `Bool`:

```links
sig ident : forall a,e::Row. (a) -e-> a
fun ident(x) { x }

fun poly(f : (forall a,e::Row. (a) -e-> a)) { (f(42), f(true)) }
poly(~ident)
```

This returns `(42, true)`. The explicit generalisation, instantiation,
type abstraction and type application forms also remain available.

`linfun` creates a linear function; `-@` and `~@` are its type arrows.
The current usage check requires one use of a linear local or parameter
along each branch of its scope. The following expression returns `42`.
Adding a second call to `f` in the block is a type error.

```links
{ var f = linfun(x) { x + 1 }; f(41) }
```

### Effect annotation syntax

The examples use the proposed notation for SmallLinks. In these forms,
`A` and `B` stand for value types, and `e` stands for a row variable.

| Form | Meaning |
| --- | --- |
| `(A) -> B` | The arrow introduces a fresh open effect row. |
| `(A) {}-> B` | The effect row is closed and empty. |
| `(A) {Ask:() => Int \| e}-> B` | The row contains `Ask`, which takes no arguments and returns `Int`, and has tail `e`. |
| `(A) -e-> B` | The effect row is `e`; this abbreviates `(A) {\|e}-> B`. |
| `(A) ~> B` | The fresh effect row contains `wild`. |
| `(A) ~e~> B` | The effect row extends `e` with `wild`. |

`wild` accounts for effects such as recursive calls and `print`.
`(A) ~> B` can also be written `(A) {wild:() | _}-> B`. The `_`
introduces a fresh row tail. `(A) {}~> B` has a closed row containing
only `wild` and can be written `(A) {wild:()}-> B`.
For example, the following signature uses an effect alias with an
explicit empty row argument:

```links
effectname Reader(a,e::Eff) = {Ask:() => a | e};

sig ask : () { |Reader(Int,{})}~> Int
fun ask() { do Ask }

handle(ask()) { case <Ask => k> -> k(42) }
```

This returns `42`. The `~>` arrow adds `wild` to the row named by
`Reader(Int,{})`.

## Algebraic effects and handlers

`do Op(args)` invokes `Op`. A nullary operation can be written `do Op`.
The effect row of the computation must admit the operation. A handler
has clauses for operation calls and for the value returned by its
computation. With no value clause, the handler returns the value
unchanged. An operation can pass through handlers until it reaches
one with a clause for it.

```links
handle(if (do Choose) 1 else 2) {
  case <Choose => k> -> k(true) ++ k(false)
  case n -> [n]
}
```

This returns `[1, 2]`. The clause can discard the resumption `k` or
call it more than once. In a deep handler, `handle`, a resumption
reinstalls the handler and has the handler's result type and output
effects. In a shallow handler, `shallowhandle`, it resumes without
the handler and has the input computation's result type and effects.
A parameterised deep handler takes initial values, and each
resumption supplies their next values.
