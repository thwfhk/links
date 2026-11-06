# Modal effects specification

This document specifies the intended language changes on `modal-effects`.
[PLAN.md](../PLAN.md) records implementation progress.
[The design](modal-effects-design.md) records implementation decisions,
reasons and reference comparisons. Section 9 states the initial effect context.

## 1. Scope

1. Add modal effect types with implicit ambient effects, following Met.
2. Use scoped rows of named effects, each grouping declared operations.
3. Replace Hindley--Milner inference with Fresco, including first-class
   polymorphism, first-class modal types and modal-kind refinement.
4. Replace existing effect annotations and migrate affected programs.

Record and variant rows retain row variables and presence types. Higher-rank
polymorphism and first-class modal types are included. Higher-order effect
declarations, explicit effect variables from Met(X), term-level masking,
database support, control-flow linearity and session failure are outside
the scope of these changes.

## 2. Syntax

### 2.1 Types and binders

In the table, `A` and `B` are types, `E` and `D` are comma-separated lists of
effect applications, and `L` is a comma-separated list of effect names.

| Form | Meaning |
|---|---|
| `List A` | List type with element type `A` |
| `(A) -> B` | Function using the ambient effect context |
| `(A) -@ B` | Linear function using the ambient effect context |
| `modal [E] A` | Absolute modality fixing the effect context to `E` |
| `modal <D> A` | Relative modality extending the ambient context by `D` |
| `modal <L \| D> A` | Relative modality removing `L`, then extending by `D` |
| `modal <> A` | Identity modality |
| `State(Int)` | Application of a named effect to type arguments |
| `forall a::Abs. A` | Type quantification restricted to absolute types |
| `forall a::Any. A` | Type quantification allowing either modal kind |

Function domains retain Links' zero-argument and multiple-argument syntax.
Modalities bind to a primary type. Parenthesise function and quantified
payloads, for example `modal [] ((Int) -> Int)` and
`modal [] (forall a. (a) -> a)`. Modal types may be nested.

Removal lists contain names without type arguments, such as `State` or
`M.State`. Extension lists contain effect applications, such as `State(Int)`.
Empty effect lists are permitted. List types use `List A`. Parenthesise
compound element types, for example `List (List Int)` and `List ((Int) -> Int)`.
The old list-type spelling `[A]` is rejected. List expressions and patterns
retain their existing square-bracket and `::` syntax.

Unannotated type binders have modal kind `Any`. Modal annotations apply to
binders and may accompany an ordinary Links kind annotation, for example
`a::Type(Any,Any)::Abs`. `::Any` retains its ordinary Links meaning and also
specifies modal kind `Any`. Repeated or conflicting annotations are rejected.
Row and presence binders retain their existing kinds; `::Abs` applies only
to value-type binders.

### 2.2 Effect declarations and invocation

```links
effect State(a::Abs) {
  Get : () => a;
  Put : (a) => ();
}
```

A declaration introduces a named effect and its operations. Parameters have
primary kind `Type` and may have ordinary and modal kind requirements.
Duplicate operation names within one declaration are rejected.
Operation signatures contain argument types and a result type. Every argument
and result must have kind `Abs`. An absolute modal function type is permitted.

Signatures may refer only to explicit declaration parameters and variables
bound by nested quantifiers. Free named variables and anonymous type, row or
presence placeholders are rejected. Declaration parameters cannot capture
outer type variables. A signature may mention its own effect; other effect
declarations follow lexical declaration order.

Invoke operations using Links' `do` syntax:

```links
do State.Get
do State.Put(42)
do M.State.Get
```

An unqualified operation name is allowed when it resolves uniquely. Effect and
operation names have separate namespaces from types, terms and variants.
`State.Get` selects the operation `Get` owned by `State`; `M.State.Get`
selects that effect through module `M`.

Unqualified lookup uses the nearest lexical scope containing that operation
name. Multiple distinct candidates in that scope are ambiguous. Opening or
importing the same declaration repeatedly preserves its identity and creates
no extra candidate. Qualified lookup first resolves the effect name.

### 2.3 Handlers

```links
handle <State(Int)> (do State.Get) {
  case x -> x
  case <Get => k> -> k(42)
  case <Put(x) => k> -> k(())
}
```

The optional `<E>` annotation selects one effect and its type arguments. Without
an annotation, the operation clauses determine the effect group. An annotated
handler resolves unqualified clause names within the selected effect, even
when another visible effect declares the same operation name. Qualified
clauses must also belong to that effect.

A handler for an effect must contain one clause for each operation in that
effect. Missing, repeated and foreign operation clauses are rejected.
Handling several effects requires nested handlers. An unannotated return-only
handler selects no effect group and remains valid.

Existing handler parameters remain supported. Shallow handlers use the same
annotation form, for example `shallowhandle <Reader> (...) { ... }`.
Repeated argument-pattern clauses for one operation must be expressed as one
operation clause containing a `switch`.

### 2.4 Freezing

`freeze(e)` freezes an expression; `~x` abbreviates `freeze(x)`.
Freezing is available in checking positions, including application arguments.
It infers `e` independently of the expected type and checks consistency with
that expected type, preserving the inferred polymorphic structure. It does
not implicitly instantiate or introduce type abstractions around that result.
Ordinary modal-access checks still apply to `e`.

## 3. Scoped effect rows and modalities

An effect row is a finite list of named effect applications. It contains no
presence specifications or effect-row variables.

1. Distinct effect names may exchange positions.
2. Repeated occurrences of one effect retain their order and type arguments.
3. Lookup selects the first occurrence of the requested effect.
4. Each removal name consumes the first remaining occurrence of that effect;
   if none is present, that removal has no effect.
5. Extension prepends its entries to the remaining row.

Row equality matches occurrences of each effect in order and requires equal
arguments for each matched pair. Subeffecting uses the same matching rule and
allows additional occurrences in the target row. For distinct effects `A` and
`B`, the contexts `A,B` and `B,A` are equal, and `A` is a subeffect of
`A,B`. The contexts `State(Int),State(Bool)` and `State(Bool),State(Int)`
differ.

For an ambient row `F`, an absolute modality `[E]` selects `E`. A relative
modality `<L | D>` selects `D` followed by `F` with `L` removed. `<D>` is
`< | D>`. Relative removal lists compare as multisets, retaining multiplicity;
extensions compare by scoped-row equality.

Modal introduction and elimination are implicit. A type annotation supplies a
modality. No new term-level boxing or unboxing syntax is required. Introduction
of leading quantifiers and modalities applies only to values. A computation
may still return a value whose type already has that structure.

To use a variable of contextual type across effect-context changes, its leading
modalities must allow those changes. Any remaining modality stays on the result.
For distinct effects `A` and `B`, a value bound at
`modal <A,B> (() -> ())` can be used at `modal <A> (() -> ())` within the
computation of a handler for `B`. Absolute types can cross context changes.
Every variable use must satisfy the access check, including uses checked
through subtyping.

## 4. Modal kinds

| Type | Modal kind |
|---|---|
| Primitive types such as `Int`, `Bool` and `()` | `Abs` |
| A contextual function type | `Any` |
| `modal [E] A` | `Abs`, for well-formed `A` |
| `modal <L \| D> A` | The kind of `A` |
| A record or variant | `Abs` when all possible payloads are absolute |
| A quantified type | The body's kind with quantified value-type binders treated as `Abs` for classification |

`Abs` types are also admissible where `Any` is allowed. `Any` permits a type
to depend on the ambient effect context. Ordinary Links kind restrictions
remain additional requirements.

Type aliases and recursive type applications are classified using their
bodies and actual arguments. Unused parameters do not affect the result.
Nested and recursive applications must account for changing arguments.
An absolute modality does not require its payload to be absolute.

Quantified-type classification follows the thesis. Classify the body with its
quantified value-type binders treated as `Abs`, retaining their ordinary kinds.
Thus both `forall a::Any. a` and `forall a::Abs. a` have kind `Abs`.
Declared binder kinds still govern well-formedness, term checking and permitted
instantiations. Row and presence binders retain their existing classification.
This classification rule does not refine a rigid variable's declared kind.

Inference may strengthen a flexible type variable from `Any` to an `Abs`
requirement. Every later solution must satisfy that requirement. An explicitly
bound rigid variable keeps its declared kind.

For records and variants, an absolute requirement propagates to contributing
flexible fields, row tails and presences. Their row/presence binder kinds stay
unchanged. A rigid row or presence variable supplies no absolute-payload
guarantee. Requirements remain valid across later definitions and scope exit.

## 5. Type inference and polymorphism

### 5.1 Fresco inference

Inference follows Fresco. Application inference combines information from the
function and its arguments, then checks the arguments against the resulting
parameter types. Annotations, expected types and freezing can supply
first-class polymorphic or modal structure.

Unknown value types are solved with monotypes, subject to kind, occurs and
scope checks. A monotype solution contains no quantifiers or modal types.
Supplied polymorphic/modal structure is retained by Fresco's instantiation
rules. Record and variant fields may carry supplied polymorphic types.

Type checking respects quantifier scope. Inferred types cannot capture or
expose type variables outside their binding scope.

For parameterised-effect transformations, try matching effects and equating
their type arguments before trying to make the payload absolute. If matching
fails, discard its inferred constraints and try `Abs` refinement from the
original context. Commit successful matching without revisiting that choice
if a later check fails. This policy may reject programs accepted by a different
choice order.

### 5.2 Bindings and annotations

1. Local bindings retain their inferred types without implicit let
   generalisation. Supplied polymorphic types remain polymorphic.
2. Explicit polymorphic annotations and quantifier introduction provide
   polymorphism. Links' explicit type abstraction and application remain
   supported.
3. Recursive definitions require signatures. All signatures in a mutually
   recursive group are available while checking its bodies.
4. Unsigned non-recursive top-level definitions retain unresolved type
   variables across later uses; these variables are not generalised.
5. A global function signature without an absolute modality receives an
   implicit `modal []`. Preserve an explicitly supplied absolute modality.
   This shorthand also applies to global recursive function signatures.

An identity with type `forall a. modal [] ((a) -> a)` can be used at both
`Int` and `Bool`. A local identity inferred with one unknown argument type
cannot be used at both types without supplying polymorphism.

### 5.3 Existing Links constructs and interactive use

Fresco checks record/variant fields, lists, tuples, patterns, branches, aliases
and recursive value types. Patterns obtain types from their scrutinee, and
branch result types must satisfy Fresco's consistency rules. Existing ordinary
linearity and session restrictions remain enforced. A modal type inherits its
payload's ordinary linearity: `Abs` does not imply `Unl`.

Retain Links' current handler behaviour with control-flow linearity disabled.
Resumptions remain reusable. The existing interaction that can duplicate or
discard a continuation holding linear values is deferred; this implementation
adds no new restrictions for that interaction.

Batch compilation and interactive definitions use the same rules.
Successful interactive definitions retain their type requirements
and declaration identities. Failed checking leaves the previous typing and
name-resolution state unchanged.

## 6. Operation and handler typing

An invocation requires its owning effect in the ambient row. It uses the
first occurrence's type arguments to instantiate the operation signature.
Argument and result types must match that instantiated signature.

Let `D` be the singleton row containing the handled effect application,
`E` the outer ambient row,
`A` the computation result type, and `B` the handler result type. The following
rules describe handlers without additional handler parameters:

| Handler component | Context or type |
|---|---|
| Handled computation | Ambient row `D ++ E`, under a relative `<D>` lock |
| Return and operation clauses | Outer ambient row `E` |
| Value bound by the return clause | `modal <D> A` |
| Argument of an operation `Ai => Bi` | `Ai` |
| Deep resumption | `(Bi) -> B` |
| Shallow resumption | `modal <D> ((Bi) -> A)` |

Every clause must produce the handler result type `B`. Existing handler
parameters retain their type checks and resumption-passing convention.

## 7. Runtime and built-in effects

Operations dispatch to the nearest enclosing handler for the resolved
operation identity. The handler is removed while its operation clause runs.
Deep resumption reinstalls it; shallow resumption leaves it removed.
Repeated effect occurrences correspond to nested handlers of the same group.
Distinct effects sharing an operation's short name remain distinct at runtime.
Modal types and freezing add no runtime evaluation constructs.

Deep handlers work in the interpreter and JavaScript backend. Shallow handlers
remain supported by the interpreter; JavaScript retains its rejection of them.

Represent external operations with the named built-in effect `Wild` and mailbox
receiving with `Receive(a)`. Both are reserved built-in effects and are
unavailable to user-written handlers. Their operations retain built-in runtime
behaviour. `Process(a)` carries the mailbox message type.
Actor messaging requires absolute message types. Spawned bodies run in their
own absolute effect context; the caller's handlers are not transferred.

Messages may have linear types as well as modal kind `Abs`. A spawned body is
a linear function, allowing it to capture linear values. Its discarded result
must have an unlimited type, as required by Links' existing spawn checks.

The actor signatures are:

```links
sig Send : forall a::Type(Any,Any)::Abs.
  modal [Wild] ((Process(a), a) -> ())
sig self : forall a::Type(Any,Any)::Abs.
  modal [Wild, Receive(a)] (() -> Process(a))
sig spawn : forall a::Type(Any,Any)::Abs, b.
  modal [Wild] ((modal [Wild, Receive(a)] (() -@ b)) -> Process(a))
```

## 8. Compatibility and examples

### 8.1 Required source changes

| Existing feature | Required replacement |
|---|---|
| List types `[A]` | `List A` |
| Handled-effect annotations `handle [E]` and `shallowhandle [E]` | `handle <E>` and `shallowhandle <E>` |
| Operation-based effect annotations and effect tails | Named effects and modal types |
| Effect-annotated arrows, including `-e->` and `~e~>` | Contextual arrows with an enclosing modality where required |
| `effectname` and effect-tail parameters | Named effect declarations and type parameters |
| Implicit Hindley--Milner let generalisation | Explicit polymorphic signatures where polymorphism is required |
| Unsigned recursive definitions | Signed recursive definitions |
| Several clauses for one operation | One clause with internal pattern matching |
| Process types parameterised by effect rows | `Process(a)` parameterised by mailbox message type |

Old effect annotations are rejected by the completed language. Existing
record/variant row and presence syntax remains supported. Type errors identify
the relevant source location, including effect names, signatures and clauses.

### 8.2 Migrating effect-annotated arrows

Use contextual arrows and place modalities around the types whose effect
requirements need to be stated. Preserve ordinary versus linear arrows as
`->` versus `-@`.

For a function requiring a fixed effect, introduce its named effect group and
wrap the function type in an absolute modality. For example:

```links
# Old signature
sig ask : () {Ask:() => Int}-> Int

# Modal declaration and signature
effect Reader { Ask : () => Int; }
sig ask : modal [Reader] (() -> Int)
```

A function using external primitives formerly marked by `~>` requires `Wild`,
for example `modal [Wild] ((String) -> ())` for printing.

For higher-order functions that share effects with their callbacks, keep the
callback arrows contextual. The old arrow structure of `map` is:

```links
((a) -e-> b, [a]) -e-> [b]
```

Its modal signature is:

```links
sig map : modal [] (forall a, b. ((a) -> b, List a) -> List b)
```

The outer `modal []` makes the definition available independently of the
caller's effects. The callback uses effects available at the call site.
Putting `modal []` around the callback type would require a pure callback.
The shared effect variable `e` is no longer needed. Global-signature sugar
also permits:

```links
sig map : forall a, b. ((a) -> b, List a) -> List b
```

For a handler argument that gains an effect while retaining the caller's
ambient effects, use a relative modality, for example
`modal <State(Int)> (() -> a)`. Choose an absolute modality when the argument
requires a fixed effect context. Apply these rules to aliases, curried
functions and stored callbacks according to where each function is used.

### 8.3 Accepted program

```links
effect Tick { Tick : () => Int; }
handle <Tick> (do Tick) {
  case x -> x
  case <Tick => k> -> k(42)
}
```

This program has type `Int` and evaluates to `42`.

### 8.4 Required rejections

1. Invoking `Tick` without `Tick` in the ambient context.
2. Handling `State` with only a `Get` clause when it also declares `Put`.
3. Declaring a bare contextual function as an operation argument or result type.
4. Treating the contexts `State(Int),State(Bool)` and `State(Bool),State(Int)` as equal.
5. Using an ambiguous unqualified operation name.
6. Allowing a local rigid type variable to escape its scope.
7. Violating a retained `Abs` requirement with a contextual function type.

## 9. Initial effect context

Batch programs and REPL commands start with ambient effect context `Wild`.
This permits direct calls to built-in external operations such as `print` and
`spawn`.
