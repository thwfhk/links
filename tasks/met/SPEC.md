# Modal effect types for SmallLinks

This is the design for modal effect types in SmallLinks. It
replaces the effect system in the [SmallLinks language
guide](../small/SPEC.md). The [plan](PLAN.md) records the work and
checks. [Implementation notes](IMPL.md) will record implementation
decisions as the work proceeds.

The examples specify the modal compiler's behaviour. The decisions
below record the review.

## Scope

1. Replace effect annotations on function arrows with modal value types
   and an ambient effect context. Group operations into declared effect
   interfaces. Use scoped rows of interface instances for effect contexts.
2. Support absolute, extension and mask modalities. Keep ordinary
   function application and the native evaluation order.
3. Keep the SmallLinks data types, modules, imports, recursive functions,
   value linearity, and deep, shallow and parameterised handlers. Adapt
   their typing and the existing polymorphism controls to modal types.
4. Switch type inference to Fresco. Use bidirectional typing for
   first-class polymorphism and first-class modal types, and reuse Links'
   unification mechanisms for monotypes where they fit. The thesis and
   Fresco implementation are the references listed at the end.
5. Write list types as `List A` and variant types with `(| |)`.
   `List` is a built-in type name and cannot be redefined. List and
   variant values keep their existing syntax.

See [Future work](#future-work) for deferred features.

## Design decisions

1. **R1. Effect interfaces.** Follow the thesis. Declare each operation
   inside an effect interface. Effect contexts name interfaces, such as
   `Reader(Int)` and `State(Int)`. Remove the old effect-row aliases;
   introduce no operation-name alias feature.
2. **R2. Top-level signatures.** Infer the type of a simple definition
   such as `fun id(x) { x }`. Require a signature when a top-level
   function uses effects supplied by its caller, such as
   `fun ask() { do Ask }`. A function that handles its own operations
   can still have its type inferred. Keep local type inference and the
   value restriction.
3. **R3. Polymorphism controls.** Keep the existing explicit polymorphism
   forms under Fresco and add `~(e)`. Use Maetel's formal rule for
   [variable access](#locks-and-values).
4. **R4. Absolute types.** Keep `Abs` separate from value linearity.
   Operation arguments, operation results and handler state parameters
   must have absolute types. Keep per-operation polymorphic signatures
   and the kind annotations described below.
5. **R5. Handlers.** Keep deep, shallow and parameterised handlers. Keep
   the thesis's checks on callbacks, returned values and resumptions.
6. **R6. Native effects.** Keep `wild` for native side effects such as
   I/O. Recursion, list ranges and installing handlers do not require
   `wild` by themselves. Their bodies require it if they call something
   with a native side effect.
7. **R7.1 and R7.4. Data type syntax.** Use `(| |)` for variant types.
   Keep `List` as a built-in type constructor; user-defined types cannot
   redefine it.
8. **R7.3. Function arrows.** Allow `A -> B` as shorthand for
   `(A) -> B` and `A -@ B` as shorthand for `(A) -@ B`.
9. **R7.2. Effect-interface declarations.** Use `effect Reader(a::Abs)
   { Ask : () => a; }` as shown under [Effect interfaces](#effect-interfaces).
10. **Range helper.** Range syntax always uses the standard pure
    `intRange` helper. See [Value restriction](#value-restriction).
11. **Unsafe cast.** Remove the unused `unsafe_cast` primitive.
12. **Explicit quantification in signatures.** Write every universal
    quantifier in a source signature. See [Types and
    annotations](#types-and-annotations).
13. **Upcasts and record updates.** Use the [checked upcast
    rules](#upcasts-and-record-updates) and reject repeated field names
    in a record update.
14. **Linear lists.** Allow linear elements in `List`. Keep `hd` and
    `tl` restricted to lists of unrestricted elements. See
    [List linearity](#list-linearity).

## Effect contexts and modalities

### Ambient function types

A typing judgement has an ambient effect context `E`. A bare function
type `(A) -> B` describes a function whose body can use `E`. Its argument
type `A` and result type `B` are interpreted in that same context.
Calling it uses the caller's ambient context, subject to the checks on
the function value's modalities and binding context. Successful
elimination of a function's outer modality exposes an ambient arrow:
its argument and result types are then interpreted in the caller's
context.

An arrow introduces no fresh effect row. For example,
`((a) -> b, List a) -> List b` gives a mapping function and its callback the
same ambient context. No effect variable is needed to express that
relationship.

Modalities can occur on any value type, including a function, record,
list element or polymorphic type. `[E] T` gives `T` a fixed effect
context. A relative modality describes a change to the ambient context.
Creating a closure does not install a handler or capture an operation's
implementation.

### Scoped rows

An effect context is a finite scoped row of effect-interface instances.
An instance gives an interface name and its type arguments. For each
interface, occurrences are ordered from newest to oldest. Occurrences
of different interfaces commute. Repeated interfaces remain distinct:

```text
{Reader(Bool), Reader(Int), State(Int)}
```

The visible `Reader` instance is `Reader(Bool)`, so its `Ask` operation
returns `Bool`. Resolve an operation to its declaring interface, then
select the newest occurrence of that interface. A type mismatch cannot
select an older occurrence.

Write `D,E` for prepending an extension `D` to a context `E`. A handler
adds one occurrence for each interface it handles. Its clauses for that
interface share the same type arguments. For example, the `Get` and
`Put` clauses of a `State(Int)` handler both use `Int`.

`E <= F` means that each sequence of instances for an interface in `E`
is a prefix of that interface's sequence in `F`. Corresponding type
arguments must agree. If `E` contains `wild`, `F` must also contain
`wild`. Extra interface occurrences in `F` are older. Thus
`{Reader(Int)} <= {Reader(Int), Reader(Bool)}` holds; reversing the two
occurrences in the right-hand context makes it fail.

Inference may solve unknown type arguments of an interface instance.
These are ordinary type variables. Effect contexts have no unknown
tails in this stage. The compiler must never add an interface to an
already fixed ambient context to make a `do` expression pass.

### Actions, composition and transformations

`E` and `F` denote effect contexts, `D` denotes an extension, and `L`
denotes a multiset of interface names to remove. Each name in `L`
removes its newest remaining instance, whatever its type arguments.
Removing an interface that is absent has no effect on the row.
Resolve these names in lexical scope. Matching and composition use
interface declaration identities, including for names from modules.

| Modality | Action on the ambient context `F` |
| --- | --- |
| `[E]` | Replace `F` with `E`. |
| `<>` | Keep `F`. This is the identity modality. |
| `<D>` | Prepend `D` to `F`. |
| `<L \|>` | Remove `L` from `F`. |
| `<L \| D>` | Remove `L` from `F`, then prepend `D`. |

Use the thesis's left-to-right composition: `(mu ; nu)(F)` means
`nu(mu(F))`. The semicolon here is explanatory notation.

```text
mu ; [E]                    = [E]
[E] ; <L | D>               = [D,(E-L)]
<L1 | D1> ; <L2 | D2>       = <L1,(L2-D1) | D2,(D1-L2)>
```

In `L2-D1`, remove one mask occurrence for each matching interface in `D1`.
In `D1-L2`, remove the newest matching extension occurrences. Preserve
the order of the remaining instances for each interface. Extending with
`Reader(Int)` and then masking `Reader` composes to identity. Masking
`Reader` and then extending with `Reader(Int)` can replace the visible
instance.

Use the thesis's modality transformation rules to check access to
values across changes of context:

1. Eliminating an absolute requirement `[E]` across a context change
   `nu` at binding context `F` requires `E <= nu(F)`. Carrying a value
   with its absolute type `[E] T` intact needs no such elimination.
2. Relative modalities can be compared by equivalence, and by the
   thesis's expansion and contraction rules. These rules pair a removed
   visible interface instance with the same interface and type arguments
   added back at the corresponding position.
3. Comparing only the resulting rows at one ambient context is
   insufficient. For example, `<>` and `<Reader |>` act alike on the
   empty row, but carry different requirements when `Reader` is present.
   Similarly, `<>` cannot generally be replaced with `<Reader(Int)>`.

These checks preserve the order of instances of each interface. They
do not search for compatible older type arguments or infer general
subtyping between interface instances.

### Locks and values

The type checker records a lock for each modal introduction and handled
computation, including when its action leaves the current concrete row
unchanged. A variable retains the context in which it was bound.
Access after locks must account for those changes.

A value of absolute type can cross a lock unchanged. For other types,
the checker uses the consecutive leading modalities to compute the
remaining modality. For example, inside a
handler for `Reader(Int)`, a value of type
`<Reader(Int), State(Int)> (() -> Int)` retains a `State(Int)`
requirement. A callback from outside the handler may be carried through
with a mask modality while remaining unavailable for a call inside it.
Check variable access across locks before instantiation. Stop at the
first quantifier when computing the remaining modality. Once access
succeeds, checking and application process the remaining prefixes in
their written order.

Reuse SmallLinks' syntactic value-restriction check for generalisation
and implicit modal introduction, with the conditions in
[Value restriction](#value-restriction). An eligible expression can be
checked under the changed context and its lock. An ineligible
computation runs in the current context before its result is bound.
An annotation cannot make an unhandled `do` expression safe by giving
its result a modal type.

## Surface syntax

### Types and annotations

The type syntax includes these forms.

```text
T ::= ... | List atomic-type | variant-type
    | (T, ...) -> T | (T, ...) -@ T
    | atomic-type -> T | atomic-type -@ T | modality T
variant-type ::= (| variant-row |)
modality ::= [absolute-entries] | <effect-entries>
           | <mask-labels | effect-entries>
absolute-entry ::= effect-entry | wild
effect-entry ::= Interface | Interface(type-arguments)
operation-signature ::= (T, ...) => T
                      | forall quantified-variables. (T, ...) => T
mask-labels ::= Interface, ...
```

`variant-row` keeps the existing variant-row grammar, including the
empty row, alternatives separated by `|`, and a final `| r` row tail.

Use `=>` for an operation signature in an interface declaration or a
handler clause annotation. A `typename` declaration, function signature,
or other value type with a `=>` arrow is rejected.

An empty argument list is `()`. Empty entries give `[]` and `<>`.
`<Reader |>` masks one `Reader` instance; `<Reader, Reader |>` masks
two. There is no term form `mask ...`. Mask entries name interfaces
without type arguments. Absolute contexts may additionally
contain the reserved permission `wild` once. It has no callable
operation signature. Relative extensions, masks and user handlers
cannot add, remove or shadow `wild`.

Modalities bind more tightly than arrows. Use parentheses around the
whole function type: `[Reader(Int)] (() -> Int)`. In
`([]((Int) -> Int)) -> Int`, only the argument is an absolute function.
In `[](((Int) -> Int) -> Int)`, the whole higher-order function is
absolute, and its callback uses its invocation context.

List types use prefix application. They bind more tightly than an
arrow. An atomic element type can follow `List` directly, as in
`List Int` or `List Maybe(Int)`. Parenthesise nested list types,
modalities, arrows, quantified types and recursive types when they
are list elements. Write `List (List Int)` and `List ([] Int)`.
The forms `List List Int` and `List [] Int` are rejected.
`[] (List Int)` is an absolute list,
`[Reader(Int)] (List (() -> Int))` is a list interpreted under
`Reader(Int)`, and `List ([]((Int) -> Int))` is a list of absolute functions.
Replace `[A]` in type annotations and printed types. List terms such as
`[]`, `[1, 2]` and `[1..3]` keep their current syntax. Other type aliases
keep their existing application syntax, such as `Maybe(Int)`.

For one argument, `A -> B` and `A -@ B` are shorthand for `(A) -> B`
and `(A) -@ B`. Keep `(A, B) -> C` for multiple arguments, `() -> C`
for no arguments, and `(()) -> C` for one unit argument. A single
tuple argument still needs `((A, B)) -> C`.

Reserve the type name `List` for the built-in list constructor.
`List A` and `List(A)` then name the same type, and the printer uses
`List A`. Existing user-defined aliases named `List`, including the
recursive variant fixtures, need renaming during migration. Preserve
their definitions and test assertions. Reject new declarations that
redefine `List`, including declarations inside modules. Type parsing
must not give the two spellings different meanings based on whitespace.

Variant types use `(| |)`:

```text
(| Nothing | Just:Int |)         closed variant row
(| Nothing | Just:Int | r |)     open variant row
(| |)                           empty variant row
```

Keep constructor terms such as `Nothing` and `Just(42)`, row and
presence variables, absent fields and existing pattern matching.
Distinct labels in a variant row keep the current data-row rules.
Keep nullary constructors, payload fields and both existing spellings
of present and absent fields. Explicit row and presence arguments keep
their existing syntax.

Square and angle brackets in types introduce modalities. Adjacent
angle brackets can delimit separate modalities in a type. In terms,
`<>` keeps its inequality meaning and symbolic operators such as
`<|>` stay intact. Parser and printer checks must cover `List`, modal
prefixes, variant rows, braced row arguments, `|>` and adjacent closing
angle brackets. Distinguish variant delimiters from existing open
record rows such as `(|r)`.

Keep `sig f : T`, parameter annotations, `e : T`, `typename`, recursive
types, and explicit `forall`. In a source `sig`, every universal
quantifier must be written. An ordinary type, data-row or data-presence
variable must be bound in the signature or already in scope. Write
`sig id : forall a. a -> a` for a polymorphic identity.
The signature `sig id : a -> a` is rejected when `a` is unbound.
For a polymorphic row tail, write a named binder such as
`forall r::Row`. A type or row hole in a signature cannot introduce
an implicit quantifier. The same rule applies whether the signature
starts with a modality or a quantifier. Unannotated definitions still
infer polymorphic types.

Remove effect-bearing arrows `{...}->`, `-e->`, `~>`, `~e~>`, and their
linear forms after migration. `->` and `-@` are the unrestricted and
linear ambient arrows. Retain `unsafe sig` as a synonym for `sig` with
the same checks; its old exemption for recursive `wild` use is no
longer needed.

### Upcasts and record updates

An upcast written `e : B <- A` checks `e` at `A` and gives it type
`B`. The checker applies the modality conversion rules at each
modal prefix. It checks list elements and variant payloads from
source to target. A variant upcast can add alternatives. For
functions, it checks arguments from target to source and results
from source to target, with the same arrow linearity.

A record upcast keeps the fields required by the target and can
omit unrestricted fields. If the target marks a field explicitly
absent, the source must establish its absence. For example,
`((x=1,y=true) : (x:Int,y{-}) <- (x:Int,y:Bool))` is rejected. An
upcast must preserve linear use of fields, including fields in an
open row. An open target record or an open source variant requires
the same row tail on both sides. Evaluation returns the original value.

A record update names each field at most once. For example,
`((x=1) with x=2,x=3)` is rejected.

### Modal record extension

When extending a closed modal record, carry the modality on the
inherited fields that need it. The new fields use the context of the
extension.

```links
effect Reader { Ask : () => Int; }
var record = ((run=fun() { do Ask }) : [Reader] (run:() -> Int));
(n=1 | record)
```

The result has type `(n:Int, run:[Reader] (() -> Int))`. Adding `n`
leaves `run` available to call in the `Reader` context.

**For review.** In `[Reader] (n{-} | r)`, `n` is absent and `r`
stands for the other fields. If `r` contains `run:() -> Int`,
returning `(n:Int | r)` outside `Reader` would lose the `Reader`
requirement on `run`. The current checker accepts extension when the
old record can be used in the current context. This works if the
context supplies `Reader` or if `r::Row(Abs)`. General extension outside
`Reader` would need a way to carry the requirement on the unknown
fields. Should we keep the current limit?

In `[Reader] (run{p})` with `p::Presence(Abs)`, `run` is either
absent or has an absolute type. For example, extending `()` gives
`(n=1)` and extending `(run=2)` gives `(n=1, run=2)`. The result
can retain the same `p` in `(n:Int, run{p})` because neither case
needs the outer `Reader` modality. The current checker rejects the
extension when it still sees the unknown presence. Should we accept
this case?

### List linearity

The linearity of `List A` follows that of the element type `A`.
Lists with linear elements must be used linearly, including when
stored inside another value. List literals, cons and append may
construct lists with linear elements. A cons pattern gives access
to both the head and the tail and checks each binding for linear
use. The `[]` pattern matches an empty list at any element type.

The built-ins `hd` and `tl` require unrestricted elements because
they discard part of the list. The same requirement applies to
other operations that discard or duplicate elements, such as
`length`, `take` and `drop`. Comprehensions that use unrestricted
collection helpers follow those helpers' element bounds.

### Effect interfaces

Use the reserved keyword `effect` to declare an interface. Each
interface has at least one operation.

```links
effect Reader(a::Abs) {
  Ask : () => a;
}

effect State(a::Abs) {
  Get : () => a;
  Put : (a) => ();
}

sig ask : [Reader(Int)] (() -> Int)
fun ask() { do Ask }
```

An interface declaration fixes its operations and their signatures.
Its parameters range over value types, with the stated kinds.
`State(Int)` supplies `Int` for `a` in both `Get` and `Put`. Distinct
declarations define distinct interfaces, even if their operation types
are the same. Provide all type arguments in annotations. A
parameterless interface appears as `[Choice] T` or `<Choice> T`.

Declare interfaces at file or module scope. Interface names have a
separate namespace from value types, so an interface `State` can coexist
with the prelude's type alias `State`. Interface names use the existing
module scope and qualification rules, as in
`Effects.Reader(Int)`. Resolve operation names in the same lexical
scope before inspecting the ambient effect context. Each reference must
identify its declaring interface and operation. Keep unqualified forms
such as `do Ask` where the name is in scope, and use module-qualified
operation names when required. Duplicate operation names within an
interface or its declaring scope are errors. `open` follows the existing
SmallLinks shadowing rules. A later interface declaration with the same
name shadows the earlier one, as with `typename`. Earlier references
keep their declaration identity, and each operation keeps the identity
of its declaring interface. Runtime labels preserve that identity.
A printed type uses an interface name that resolves to the same
declaration when such a name is in scope. If no source name is in
scope, the printer marks the declaration as out of scope. Diagnostics
distinguish declarations that share a name.

Imports follow the same rules as imports of `typename` declarations.
Within one dependency pass, repeated imports share the same module.
When a later input loads the module again, new references use the
newly loaded declarations and earlier references keep their identities.

Interface parameters and an operation's own quantifiers are separate.
An instance fixes the interface parameters for all its operations and
calls. A `forall` on an operation signature is instantiated separately
at each call. This retains SmallLinks' polymorphic operations under R4.

An operation signature can refer to its own interface and to earlier
interfaces in scope. For example, an interface can accept a function
whose absolute effect context contains an instance of that interface.
The argument and result types must still satisfy `Abs`.

Remove `effectname` and operation fields from effect annotations.
Effect contexts and masks use interface names. Record and variant
aliases, rows and presence fields keep their existing meanings.

## Absolute types and existing kinds

An absolute type describes values whose interpretation is independent
of the ambient effect context. The restriction is `Abs`:

1. Base types and `()` are absolute.
2. A tuple, record, variant or list is absolute when all its components
   are absolute. An open data row also needs an absolute tail. An
   unknown field presence must permit only absence or an absolute
   payload, including after later instantiation.
3. `[E] T` is absolute even when `E` contains operations. Calling a
   function inside it still requires a compatible effect context.
4. An ambient function type is generally not absolute. A relative
   modality preserves absoluteness when its body is already absolute.
5. Quantified and recursive data types use these rules for their bodies.
   Recursive checks must preserve restrictions through every field.

SmallLinks tracks primary kind (`Type`, `Row` or `Presence`), value
linearity and type restrictions. `Base` restricts a type variable to
primitive types such as `Int`, `Bool` and `String`. A non-identity
modality such as `[]` in `[] Int` puts the type outside `Base`.
In a row tail such as `(x:Int | r::Base)`, `Base` restricts the
types of the remaining fields. The prelude uses it for ordering keys.
`Abs` tracks independence from the ambient effect context.

Use `a::Abs` for an absolute value type, with the same linearity
default as `a::Type`. The full spellings are
`a::Type(Any,Abs)` for a possibly linear absolute value,
`r::Row(Abs)` for an absolute data-row tail, and `p::Presence(Abs)`
for an absent field or a field with an absolute payload. The internal
representation should express the independent constraints clearly.

`Abs` does not imply `Unl`, `Base` or `Mono`. `Base` implies both
`Abs` and `Mono`.
Fresco's unification metavariables range over monotypes. Explicit
`Mono` annotations also restrict a programmer-written type variable.
Use `MonoAbs` as shorthand for both `Mono` and `Abs`, including in
`Type`, `Row` and `Presence` kinds. Effect-variable kinds are postponed.

Operation arguments and results must be absolute, including any
quantified variables on which they depend. A raw callback `(Int) -> Int`
cannot be an operation payload. `[]((Int) -> Int)` or
`[Reader(Int)] ((Int) -> Int)` can be a payload. This supports fixed
higher-order operation interfaces without effect variables.

Preserve value-linearity checks for closures, parameters and branches.
An absolute linear closure still requires linear use. Keep SmallLinks'
existing behaviour for multi-shot resumptions, including replay of a
captured computation which uses a linear value.

## Inference and required annotations

### Fresco inference

The switch to Fresco is settled. Current SmallLinks combines
unification-based inference with FreezeML-style first-class
polymorphism. Fresco uses bidirectional inference and checking to infer
first-class polymorphism and first-class modal types. Its inference
algorithm also unifies monotypes.

Reuse Links' monotype unification, data-row and presence solving,
occurs checks and type-variable operations where they satisfy Fresco's
requirements. Fresco controls when to instantiate or introduce
quantifiers and modalities, how expected types flow into expressions,
and how known polymorphic or modal structure determines instantiation.
Unification alone cannot make those decisions. Keep the boundaries
between these responsibilities clear when restructuring the checker.

### Value restriction

Use SmallLinks' existing `TypeSugar.is_generalisable` check as the basis
for generalisation and implicit modal introduction. It checks the
expression's syntax before introducing quantifiers or modalities.

1. Variables, literals, function literals and eligible aggregates pass.
2. Projections, annotations and explicit polymorphism forms pass when
   their underlying expressions pass.
3. Conditionals pass when the condition and both branches pass. Blocks
   pass when their bindings and final expression pass, including the
   existing check that binding patterns cannot fail.
4. Function calls, operation calls and handler computations fail.
   An empty effect context alone does not make a call eligible.

A binding that can fail a pattern match is ineligible. This includes
variant patterns when the matched type allows another alternative.
A computation may return a value whose type is already polymorphic
or modal. An expected type cannot introduce fresh quantifiers or
modalities around an ineligible computation.

Apply the check after module desugaring, so module and import
initialisers are checked as actual bindings. Adapt it to the changed
syntax and omit `escape` from the supported fragment. Keep modal locks,
ordinary typing and linearity checks. Elaborating an eligible
conditional, projection or block must preserve evaluation order and
evaluate it once. This extends the thesis's value-only introduction
rule to the pure expressions already recognised by SmallLinks.

Range expressions pass the check when their bounds pass. Range syntax
always uses the standard pure `intRange` helper, even if a binding
shadows that name. Explicit calls to `intRange` follow ordinary name
lookup. Test both forms with a local binding for `intRange`.

### Binding rules

R2 keeps inference for simple top-level functions:

1. Insert a `[]` lock before inferring an unannotated global named
   function under the empty effect context. Introduce `[]` around its
   inferred function type, and generalise eligible value-type, data-row
   and data-presence variables.
   This also applies to named functions in modules, top-level `op`
   definitions and REPL definitions.
2. A global function signature without a leading absolute modality,
   after its leading quantifiers, receives an outer `[]`. A signature
   with a leading absolute modality uses that context. A global relative
   signature receives the same outer `[]` convention.
3. Local functions and `var` bindings use their current context.
   Generalisation follows the SmallLinks value restriction and excludes
   variables free in the term environment, ambient context and binding
   locks. It does not invent modalities, generalise an ambient context,
   or erase binding locks. In particular, a type argument shared by an
   interface instance cannot become polymorphic through a local function
   that calls one of its operations. Effectful initialisers run before binding
   their results.
4. Unannotated recursion is monomorphic within its recursive group,
   followed by eligible generalisation. Polymorphic recursion requires
   signatures. Local recursive functions keep their surrounding context;
   global recursive functions follow the global rule.

In the following example `f` only calls itself with `Int`. The
signature puts `forall a` inside the result of the outer arrow.

```links
sig f : Int -> (forall a. a -> a)
fun f(n) { if (n == 0) fun(x) { x } else f(n - 1) }
var g = f(1);
(g(42), g(true))
```

This returns `(42, true)`. Without the signature, generalisation
gives `f` type `forall a::Any. [] (Int -> (a -> a))`. Each call to
`f` chooses `a` once for the returned function. The call `f(1)` is
ineligible for generalisation, so the two uses of `g` must agree
on its argument type.

The inserted global lock also checks captured top-level `var` values.
For example, a global function inferred under `[]` cannot call a
captured ambient function which requires the top-level `wild` permission.
Even `var f = fun() { 42 }; fun g() { f() }` requires an annotation:
the `var` gives `f` an ambient function type. Writing
`var f = (fun() { 42 } : [](() -> Int));` lets `g` use it. Apply the
same rule across modules and REPL sentences.

An unannotated global `fun ask() { do Ask }` therefore fails. Give it
`[Reader(Int)] (() -> Int)`, or check a lambda at an expected relative
type supplied by a handler function. The compiler does not infer a
minimal closed effect context from an unannotated body. A global
function that handles its own operations can still infer under `[]`.

The native top-level expression and top-level `var` initialisers use
`{wild}`.
A global function body gains `wild` through its signature when needed.
A top-level `var` whose type still depends on its binding context keeps
that dependency when imported or used in another scope; importing it
cannot grant it `[]`.

### First-class polymorphism and modal types

Use Fresco's separation of partial type information from full checking.
Applications can obtain known type structure from an argument and pass
the function's expected modalities back to that argument. This is
needed for a handler applied to an unannotated lambda. Partial type
inference uses the operation's declared result type, with unknown
interface arguments where necessary. Full checking selects the visible
interface instance and checks its type arguments and availability.

Infer instantiation with polymorphic or modal types when that structure
is supplied by an annotation, a known value type or an expected type.
Unresolved type variables do not guess new `forall` or modal structure.
An unannotated parameter used at both `Int` and `Bool` needs a
polymorphic parameter annotation or an expected polymorphic type.

Keep `~ident`, `~fun`, `~linfun`, `$(e)`, `e@`, `/\ [a]. { e }`
and `e[T]`. Frozen function definitions keep their existing explicit
polymorphism role and obey the same modal checks. Extend
freezing to `~(e)` to use Fresco on a compound expression. Parentheses
preserve freezing, so `~x`, `~(x)` and `~((x))` agree. Freezing
preserves the type obtained after lock checks, including its quantified
and modal structure, and uses Fresco's consistency check without further
implicit instantiation. `$(e)` retains the value restriction. Effect
arguments are postponed.

Explicit type application and `e@` preserve surrounding modalities.
Given `f : [Reader(Int)] (forall a. (a) -> a)`, `(~f)[Int]`
retains `[Reader(Int)]`; calling it still requires `Reader(Int)`. Keep type
variables in scope and compose adjacent modalities in their written
order. To use explicit type application to expose a modality beneath
a quantifier before crossing a lock, bind the applied value outside
that lock. The printer preserves the order of quantifiers and
modalities, including in `forall a. [] T` and `[] (forall a. T)`.

Keep inferred `Abs` restrictions in generalised types. Parameterised
interfaces can leave a choice between making an unknown value type
absolute and equating interface arguments. For example, comparing
`<Reader(a)> T` and `<Reader(b)> T` may depend on whether `T` is
absolute or whether `a` and `b` agree. A comparison already holds if
`T` is known to be absolute or the arguments agree. Use information
from later constraints. Request a type or parameter annotation when
that information still leaves a choice. The result must be independent
of constraint order. The thesis describes the two alternatives. The
annotation requirement is a SmallLinks rule.
Without an expected type, branches must agree without introducing
a new polymorphic or modal common type.

When inferring the result of an `if`, `switch` or handler, relative
prefixes do not affect agreement once the common underlying type is
known to be absolute. For example, branches of type `<Reader(Int)> Int`
and `<Reader(Bool)> Int` both yield `Int`.

### Annotation summary

| Situation | Required information |
| --- | --- |
| Pure global function, ordinary local function, ordinary recursion | Infer the ordinary type under the context supplied by the binding rules. |
| Global function requiring an operation from outside its body or a native effect | A signature giving an absolute context, or another expected modal type. |
| Lambda supplied to a known handler function | Infer its ordinary type and check its body using the expected relative modality. |
| Higher-rank or modal parameter whose structure is otherwise unknown | A parameter annotation or expected function type. |
| Polymorphic recursion | A signature for each polymorphically recursive function. |
| Polymorphic operation | A quantified signature in its interface declaration. Each `do` instantiates the operation's own quantifiers separately. |
| Ambiguous interface argument or absolute-kind constraint | A signature fixing the unresolved choice. |
| Effect-variable abstraction or generic higher-order effect interface requiring it | Postponed. |

## Operations and handlers

### Operations

Keep `do Op(args)` and nullary `do Op`. Resolve `Op` to its declaration
and select the newest instance of its owning interface. Substitute that
instance's type arguments into the declared operation signature, then
instantiate the operation's own quantifiers at this call. Evaluate
arguments in the current context and check arity, types and `Abs`.

For example, every `Get` and `Put` using one `State(a)` instance shares
the same `a`. An operation can also have its own quantifier:

```links
effect Failure {
  Fail : forall a::Abs. () => a;
}
```

Each call to `Fail` may choose a different absolute result type. A
handler checks its clause with a rigid `a`; it cannot manufacture a
result of arbitrary type. An aborting clause can discard its resumption
and return the handler's result type.

### Deep handlers

For a handler in context `E`, let `D` contain the interface instances
handled by its clauses, `A` be the input computation's result type,
and `B` be the whole handler's result type. Infer one set of type
arguments per interface, shared by all its clauses.

1. Check the handled computation in `D,E`, behind a lock `<D>`.
2. Check return and operation clauses in `E`.
3. Bind the return value at `A` when `A` is absolute, and at `<D> A`
   otherwise. Pattern matching
   must carry this dependency into fields whose types depend on the
   context.
4. For `Op:(P) => Q`, bind its argument at `P` and its deep resumption
   at `(Q) -> B` in `E`. Calling the resumption reinstalls the handler.
5. All clauses return `B`. An omitted return clause means the same
   checked `case x -> x` as an explicit identity clause.

Get each clause's operation signature from the interface declaration.
Infer the interface's type arguments from patterns, calls, resumption
arguments and expected types. A clause annotation must agree with the
declared operation scheme and may constrain the shared interface type
arguments. It cannot specialise the operation's own rigid quantifiers
or declare a new operation. Preserve both existing resumption
binders `=> k` and `-> k` for deep and shallow clauses.

A handler must provide clauses for every operation of each interface
it installs. Several pattern clauses for one operation share its
signature. If all their patterns fail, evaluation raises the existing
match error. Operations of other interfaces are forwarded to the
enclosing handlers.

To forward one member in a deep handler, write an explicit clause that
invokes the operation in the enclosing context and resumes with its
result. A parameterised deep handler also passes its current state to
the resumption. A shallow resumption still needs its handled interfaces:
preserving an omitted clause's old forwarding behaviour requires
re-establishing the shallow handler, including its return clause,
around that resumption. Separate interfaces may provide a simpler
translation for those programs.

Complete coverage matters because an older instance may have different
type arguments. An inner `State(Bool)` handler with only `Get` must not
send `Put(true)` to an outer `State(Int)` handler.

Keep SmallLinks' ability to combine operation clauses from several
interfaces in one handler. Each interface is complete and contributes
one occurrence to `D`. A return-only handler has an empty `D`.

The default return clause cannot silently discard `<D>` from a
returned closure. It may return a value whose type retains the
modality; using that value later requires an appropriate context.
Normalise adjacent modal prefixes by composition and remove the
identity prefix. In particular, returning a mask-typed value through
the corresponding handler can restore its ambient type. Transforming
a computation's result must evaluate that computation once in its
current context before transforming the resulting value.

### Shallow and parameterised handlers

A shallow handler checks the same input and clause contexts as a deep
handler. Its resumption has type `<D> ((Q) -> A)`: it returns the input
computation's result and does not reinstall the handler. A new handler
for `D` permits calling it. The presence of an older instance of the
same interface alone does not remove this relative dependency.

Check uses of captured linear values across the return and operation
clauses of a shallow handler as alternative branches. A captured
linear value used in a clause must be used once in every clause,
including the implicit return clause when present. This is a static
check on clause paths. The existing resumption rules allow an
enclosing handler to abort or replay the computation.

For a parameterised deep handler with state types `S1, ..., Sn`, the
resumption has type `(Q, S1, ..., Sn) -> B` in `E`. Evaluate initial
state expressions from left to right in `E`, with the same bindings
in scope for each expression. Count uses of linear values across all
initial expressions in sequence. Only the clauses bind the current
state. Each resumption call supplies its next state. Each `Si` must be
absolute.

#### Linear state

Each operation and return clause must use every linear state binding
once on each branch. The implicit return clause leaves the state
unused, so linear state requires an explicit return clause. Passing a
linear state value to a resumption as its next state counts as one use.
This is a static check on each clause. When an enclosing handler
resumes a captured computation twice, the existing replay rule also
applies to the captured handler state.

The following handler returns `43`:

```links
handle(42)(f <- (linfun() { 1 } : [](() -@ Int))) {
  case n -> n + f()
}
```

Changing the clause to `case n -> n` discards `f` and is rejected.
Calling `f` twice in a branch is also rejected.

## Native effects

Use `wild` for native side effects. Printing, socket I/O, reading the
current time, random generation and `gensym` require it. A primitive
that only computes a result receives a pure type. A primitive that can
use a native effect for any input requires `wild` at every call.
`show` uses the local time zone when formatting a date, including
a date in a container. `parseDate` uses it when the string has no
offset. Both require `wild`. `sleep` has the timing permission
even while it reports that it is unimplemented. `error` is a
deterministic runtime failure and has a pure type.

For example, `print` has type `[wild] ((String) -> ())`. A function
that calls `print` must include `wild` in its effect context. Files,
top-level expressions and the REPL provide `wild`, so they can call
such functions. User-defined handlers cannot handle or add `wild`.

The built-in `exit` ends the current evaluation with its argument and
requires `wild`.
Its argument must have an absolute, unrestricted type. Its result type
can be instantiated independently at each call and is unrestricted.
The signature is `forall a::Abs,b. [wild] ((a) -> b)`.

Recursion, range construction and installing an algebraic handler add
no `wild` requirement themselves. For example, factorial can have a
pure type, and a handler that only computes integers can have a pure
type. A recursive function that prints still requires `wild` because
it calls `print`.

`escape` is outside the first modal version. Give its use a clear
unsupported-feature diagnostic and record dependent examples as
deferred. Keep the continuation machinery needed by handler resumptions.

## Accepted and rejected programs

Use these interface declarations for the examples below. Each program
is otherwise independent unless it refers to a preceding definition.
Types below use explicit modalities even where the global convention
allows omission. These are acceptance criteria for implementation.

```links
effect Reader(a::Abs) { Ask : () => a; }
effect State(a::Abs) { Get : () => a; Put : (a) => (); }
effect Choice { Choose : () => Bool; }
effect Tick { Tick : () => (); }
effect Next { Next : () => Int; }
effect Failure { Fail : forall a::Abs. () => a; }
```

### 1. Inferred pure and higher-order functions

```links
fun ident(x) { x }
fun apply(f, x) { f(x) }
(ident(42), ident(true))
```

Accept and return `(42, true)`. Infer `ident` as
`forall a. []((a) -> a)` and `apply` as
`forall a,b. [](((a) -> b, a) -> b)`. The parameter `f` shares the
invocation context of `apply`.

```links
handle(apply(fun(x) { x + do Ask }, 1)) {
  case <Ask => k> -> k(41)
}
```

With the preceding `apply`, accept and infer result `Int`; return `42`.
Infer the handled instance `Reader(Int)` from the body and clause.
No effect variable or callback annotation is required.

### 2. An effectful definition needs an expected context

```links
sig ask : [Reader(Int)] (() -> Int)
fun ask() { do Ask }

handle(ask()) { case <Ask => k> -> k(42) }
```

Accept and return `42 : Int`. Removing the signature rejects the
global definition because its inferred body context is empty.
Keeping the signature but calling `ask()` at the native top level
rejects the call because `{wild}` has no `Reader` instance.

### 3. A relative callback supplies handled effects

```links
sig withAsk : forall a::Abs. []((<Reader(Int)> (() -> a)) -> a)
fun withAsk(action) {
  handle(action()) { case <Ask => k> -> k(42) }
}

withAsk(fun() { do Ask + 1 })
```

Accept, infer the callback result as `Int`, and return `43`. The
expected `<Reader(Int)>` checks the callback body with `Ask`
available. Changing the parameter type to a bare `() -> a` rejects
`action()` inside the handler: that call could use a newly handled
operation belonging to the callback's caller.

### 4. Absolute callback requirements

```links
sig pureCall : [](([](() -> Int)) -> Int)
fun pureCall(action) { action() }

pureCall(fun() { 42 })
```

Accept and return `42`. The following call is rejected even though
there is an enclosing `Reader(Int)` handler. The argument's `[]` requires its
body to check with no operations.

```links
handle(pureCall(fun() { do Ask })) {
  case <Ask => k> -> k(42)
}
```

### 5. Repeated interface instances

```links
handle(
  handle(if (do Ask) 1 else 0) {
    case <Ask => k> -> k(do Ask == 42)
  }
) {
  case <Ask => k> -> k(42)
}
```

Accept and return `1 : Int`. The inner computation sees
`{Reader(Bool), Reader(Int), wild}`. The inner clause runs in the
outer context, so its `do Ask` returns `Int`.

```links
handle(
  handle(do Ask + 1) { case <Ask => k> -> k(true) }
) {
  case <Ask => k> -> k(42)
}
```

Reject: the inner `Ask` must return both `Int` and `Bool`. The older
`Reader(Int)` instance cannot satisfy the call in the inner computation.

### 6. Handler results retain their dependencies

Using `withAsk` from example 3:

```links
withAsk(fun() { fun() { do Ask } })
```

Reject: the callback returns an ambient function type `() -> Int`,
which cannot instantiate `a::Abs`.

```links
withAsk(fun() { (fun() { do Ask } : [Reader(Int)] (() -> Int)) })
```

Accept with result type `[Reader(Int)] (() -> Int)`. Its signature
records the returned function's requirement. Calling it requires a
compatible `Reader(Int)` handler. The same rule applies to a returned
record such as `(run=fun() { do Ask })`; hiding the closure in a field cannot
remove its dependency.

```links
var delayed = handle(fun() { do Ask }) {
  case <Ask => k> -> k(42)
};
handle(delayed()) { case <Ask => k> -> k(42) }
```

Accept and return `42`. Infer `delayed` as
`<Reader(Int)> (() -> Int)`. Replacing the final handler with
`delayed()` is rejected. The default return clause preserves the
relative dependency on the handled interface.

### 7. Mask modalities without term masks

```links
sig hold : []((() -> Int) -> (() -> Int))
fun hold(f) {
  handle({
    do Tick;
    (f : <Tick |>(() -> Int))
  }) {
    case <Tick => k> -> k(())
  }
}

hold(fun() { 42 })()
```

Accept and return `42`. Within the handled computation, `f` carries
the mask `<Tick |>`. The return binding adds `<Tick>`;
extension followed by masking cancels, so `hold` returns the callback
at its original ambient type. The function value is carried through
the handler without calling it there.

Replacing `(f : <Tick |>(() -> Int))` with `f()` and changing the
declared result to `Int` is rejected. Calling `f` there would expose it
to the new `Tick` handler. No annotation or implicit coercion may
insert runtime masking to make that call pass.

### 8. Multi-shot and shallow resumptions

```links
handle(if (do Choose) 1 else 2) {
  case <Choose => k> -> k(true) ++ k(false)
  case n -> [n]
}
```

Accept and infer `List Int`; return `[1, 2]`. The deep resumption has
type `(Bool) -> List Int` in the outer context.

```links
shallowhandle(do Next + do Next) {
  case <Next => k> ->
    handle(k(20)) { case <Next => next> -> next(22) }
}
```

Accept and return `42`. The shallow resumption has type
`<Next> ((Int) -> Int)`. Replacing its clause body with
`k(20)` is rejected because that relative requirement remains.

### 9. Parameterised state

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

Accept and return `42`. Infer one `State(Int)` instance, state type
`Int` and result type `Int`. `Get` and `Put` share that instance's
type argument. The resumption types are
`(Int, Int) -> Int` and `((), Int) -> Int`. Changing a supplied state
value to `true` is rejected.

### 10. Higher-rank parameters and freezing

```links
sig ident : forall a. []((a) -> a)
fun ident(x) { x }

fun both(f : (forall a. []((a) -> a))) { (f(42), f(true)) }
both(~ident)
```

Accept and return `(42, true)`. The parameter annotation supplies the
polymorphic structure; freezing preserves `ident`'s supplied type.
Removing the parameter annotation rejects the two uses of the
monomorphic parameter `f`. Modal checking alone does not infer that
parameter's universal quantifier.

### 11. Polymorphic operations

```links
sig failTwice : [Failure] (() -> Int)
fun failTwice() { if (do Fail) 42 else do Fail }

handle(failTwice()) {
  case <Fail> -> 0
}
```

Accept and return `0`. The calls instantiate the operation's own result
variable at `Bool` and `Int`. The `Failure` instance is the same for
both calls. A clause binding `k` and calling `k(42)` is rejected:
`42` cannot supply the arbitrary rigid result type `a` from `Fail`'s
declaration.

### 12. Modal introduction and operation payloads

```links
var f = ((if (true) fun(x) { x } else fun(x) { x }) : []((Int) -> Int));
f(42)
```

Accept and return `42`. The condition and both branches pass the
SmallLinks value-restriction check. Check the expression under the
absolute lock. A projection from a record of eligible expressions and
a block of eligible bindings can introduce a modality in the same way.

```links
var bad = (do Ask : [Reader(Int)] Int);
```

Reject at the native top level. The non-value `do Ask` executes with
`{wild}`, where the operation is unavailable.

An interface declaring `Run : ((Int) -> Int) => Int` is ill-formed
because its payload is an ambient function. Declaring
`Run : ([]((Int) -> Int)) => Int` is well-formed. An argument
`fun(x) { x + do Ask }` cannot satisfy that pure payload type even
inside a `Reader(Int)` handler.

### 13. Native permissions

```links
sig say : [wild] ((String) -> ())
fun say(s) { print(s) }

say("hello")
```

Accept, print `hello` and return `()`. Giving `say` the signature
`[]((String) -> ())` rejects the native call.

### 14. List and variant types

```links
sig keepInts : []((List Int) -> List Int)
fun keepInts(xs) { xs }

keepInts([20, 22])
```

Accept and infer `List Int`; return `[20, 22]`. Nested lists have types
such as `List (List Int)`. The term syntax for lists is unchanged.

Variant construction and matching keep their current term syntax:

```links
typename MaybeInt = (| Nothing | Just:Int |);
var value = Just(42) : MaybeInt;
switch (value) {
  case Nothing -> 0
  case Just(n) -> n
}
```

Accept and return `42 : Int`. Annotating `Just(true)` with `MaybeInt`
is rejected because the `Just` payload must have type `Int`.

### 15. Complete interfaces and forwarding

```links
handle(if (do Choose) do Ask else 0) {
  case <Choose => k> -> k(true)
  case <Ask => k> -> k(42)
}
```

Accept and return `42`. This handler installs both `Choice` and
`Reader(Int)`, with every operation of each interface covered.

```links
handle(
  handle({ do Put(7); do Get }) {
    case <Put(n) => k> -> k(())
    case <Get => k> -> k(do Get)
  }
)(state <- 42) {
  case <Get => k> -> k(state, state)
  case <Put(n) => k> -> k((), n)
}
```

Accept and return `42`. Both handlers install `State(Int)`. The inner
handler discards writes and explicitly forwards reads: its `Get`
clause invokes the outer `Get` because clauses run in the enclosing
context. Removing the inner `Get` clause is rejected as incomplete.

In particular, this incomplete interface handler must be rejected:

```links
handle(
  handle({ do Put(true); do Get }) {
    case <Get => k> -> k(false)
  }
)(state <- 0) {
  case <Get => k> -> k(state, state)
  case <Put(n) => k> -> k((), n)
}
```

The inner handler would install `State(Bool)` but has no `Put` clause.
The outer `State(Int)` handler cannot provide the missing operation.

## Migration and deferred coverage

1. Translate ordinary same-context callbacks such as `map`, composition
   and folds to ambient arrows. Most existing effect-variable examples
   use one ambient effect variable and belong in this migration.
2. Translate a closed effect requirement to an absolute modality on the
   value which needs it. Translate a handler's callback requirement to
   a relative extension. Classify each open-row signature by its use;
   do not mechanically copy its fields to every arrow.
   Declare shared interfaces and replace operation fields and old
   `effectname` aliases with interface instances. Partial handlers of
   one interface need the forwarding treatment described under
   [Deep handlers](#deep-handlers). Keep existing forwarding behaviour
   when making that change, including the state handlers in
   `light_switch` and `transaction`.
3. Keep data-row and data-presence polymorphism, including explicit
   type arguments, and migrate the surrounding function signatures.
4. Among existing effect-variable programs, postpone only those whose
   modal translation still requires multiple independent effect
   variables simultaneously.
   For each deferred program, record which independent effect contexts
   must be related and why the modalities in this stage cannot express
   the relationship. The original number or spelling of effect
   variables alone does not justify deferral. Tests dedicated to the
   postponed effect-variable syntax also remain deferred; translate
   tests of program behaviour whenever one ambient context suffices.
5. Postpone reference examples requiring term masks, including tests
   that make a callback bypass a handler. Keep tests of mask types,
   composition, transformation and value transport.
6. Review effect-dependent helpers such as `Comp` and `gen0`–`gen2`,
   and examples such as pipes, fringe and SAT individually. Update
   uses that can be expressed with modalities. Record any remaining
   dependency on a postponed feature, including aggregate example
   runners and registration entries.
7. Keep runtime regression coverage for forwarding, clause contexts,
   failed patterns, multi-shot resumptions and all native entry points.
   Add accepted and rejected tests for each rule above, and parse the
   type printer's output again as source annotations.
8. Migrate list and variant type annotations, printed types, primitive
   signatures and fixtures to the reviewed syntax in milestone 2.
   Record `escape` examples and tests as deferred. Keep shared
   continuation code used by handlers.
9. Keep the [lambda evaluator](MIGRATION.md#installed-examples) deferred
   for this version. See [modality-parameterised
   handlers](#modality-parameterised-handlers) for the proposed extension.

## Future work

1. **Effect variables and effect quantification.** Ordinary value,
   data-row and data-presence variables remain available. The
   [migration rules](#migration-and-deferred-coverage) identify examples
   that need independent effect contexts.
2. **Term-level masks.** Mask modalities remain available in types.
   A term-level mask would let evaluation bypass a handler.
3. **Modality elimination across quantifiers.** The Maetel chapter
   proposes considering the whole sequence of leading quantifiers
   and modalities for lock access and subtyping. Defer that extension,
   including composing modalities across a still-bound quantifier
   and moving quantifiers during lock access.
4. **Complete inference for parameterised modality conversions.**
   The thesis leaves open how to choose between an absolute body
   and equal interface arguments without losing completeness. SmallLinks
   uses the annotation rule in [First-class polymorphism and modal
   types](#first-class-polymorphism-and-modal-types).
5. **`escape`.** Handler resumptions remain available. The migration
   inventory lists the examples and tests that require `escape`.

### Modality-parameterised handlers

The thesis gives the typing rule for shallow handlers in §5.7
“Shallow handlers” (Figure 5.7) and the rule for modality-parameterised
deep handlers in §5.8 “Modality-parameterised handlers” (Figure 5.8).
The SmallLinks proposal would combine these two rules.

Explore letting a handler specify the modality from the clause context
to the handled computation and using it in the type of a shallow
resumption. The current rule uses the relative extension `<D>` for
the interfaces `D` installed by the handler. The existing parameterised
deep handlers take state values.

Work out when a shallow handler can use a fixed input context `E` and
give its resumption a type such as `[E] ((Q) -> A)`, where `Q` is the
operation result type and `A` is the handled computation's result type.
Before restoring the lambda evaluator, check that the wrapper for the
`Lam` resumption has the absolute type `Expr(a)` that `Var` must return.
Check that later `Lam` calls reach the newly installed handler, including
when an older `Lam` handler is in scope, and that other operations
still reach the enclosing handlers.

## Design and implementation references

The thesis checkout is `~/code/latex/phd-thesis`:

| Source | Design used here |
| --- | --- |
| `chapters/overview.tex`, Pure programs through Type inference | Effect interfaces, ambient arrows, higher-order functions, absolute kinds and annotation examples. |
| `chapters/met/met-calculus.tex`, Mode theory and Typing | Scoped rows, modalities, locks, value restriction and deep handlers. |
| `chapters/met/extensions.tex`, Masks, Parameterised effects, Crisp data types and Polymorphism | Mask algebra, scoped interface arguments, dependent fields and polymorphism. |
| `chapters/met/extensions.tex`, §5.7 “Shallow handlers” and §5.8 “Modality-parameterised handlers” | Shallow resumptions and the deep-handler rule that supplies the modality parameter for the proposed extension. |
| `chapters/maetel/maetel.tex`, First-class modal types, Type inference algorithm, Extensions and design choices | Fresco inference, residual modalities, kinds, global annotations and leading quantifiers. |

The implementation checkout is
`~/code/type/frost/paper/artifact/freso-implementation`:

| Source | Implementation reference |
| --- | --- |
| `README.md` | Algorithm-to-function map and example organisation. |
| `lib/syntax.ml`, `lib/parser.mly` | Modal types, kinds and source syntax. |
| `lib/effects.ml`, `lib/context.ml` | Scoped occurrence removal, composition, residuals and locks. |
| `lib/type.ml` | `finfer`, `sk_infer`, consistency, subtyping, modal checking and handlers. |
| `tests/pass`, `tests/fail`, `tests/fresco` | Positive and negative typing cases, including known modal structure and freezing. |

The reference uses declared groups of operations and one deep handler
form. SmallLinks uses effect interfaces as well, and also retains local
generalisation, data rows, per-operation quantifiers and its other
handler forms. Its runtime runs return and operation clauses in the
enclosing context. Adapt the reference code for these features, complete
interface coverage and declaration-based operation lookup.
