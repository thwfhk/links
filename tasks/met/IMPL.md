# SmallLinks modal effect types implementation notes

The [specification](SPEC.md) contains the approved language design.
The [plan](PLAN.md) contains milestones, status and check results.

As each milestone proceeds, record significant implementation decisions
under its heading. Include the affected source, the reason for the
decision and any effect on the approved specification. Link to the plan's
checks. Keep language-design questions in SPEC.md until they are resolved.

## Implementation approach

Reuse existing Links code where it fits the new design, including its
monotype unification mechanisms. Restructure or rewrite code when that
significantly improves its structure and clarity. Record substantial
decisions here as implementation proceeds.

## 1. Reviewed design and baseline

The design review and [baseline checks](PLAN.md#implementation-baseline)
are complete. See the [migration inventory](MIGRATION.md) for the
affected signatures, tests and examples.

Removed `unsafe_cast` from the native primitive table in `core/lib.ml`.
Checked upcasts use IR coercions. `tests/native.tests` checks that the
primitive is unavailable.

## 2. Syntax, types and scoped contexts

The parser reads `List A` and `List(A)` through the same constructor.
`List` remains available as a term constructor. Both type printers
group compound list elements and print variant absences as `Label{-}`.
The parser shares the grammar for open-only record and variant rows
until their closing delimiter distinguishes them.

`ModalEffects` stores interface instances newest first for each
declaration. It stores `wild` separately and takes argument equality
from the caller. `Unify` checks the shape of two modalities before
unifying corresponding arguments. Relative transformations contract a
matching mask and extension at the binding context. A residual that
restores repeated interface instances starts after the occurrences
the requirement still masks. This preserves the type arguments in
`<Reader, Reader |>` followed by restoration to `<Reader |>`, where
the first two occurrences can have different arguments.

`DesugarModules` resolves effect interfaces and operations in their
own namespaces. Each declaration has an identity, including when two
modules use the same names. The operation registry maps the runtime
label back to that identity and the declared signature. A declaration
can refer to itself. Later declarations follow ordinary left-to-right
lookup. Failed REPL sentences and loads restore the prior name scope.

The front end registers operation signatures and checks declared kinds,
including absolute operation arguments and results. It lowers modal
syntax to `Types.Modal` and ambient arrows to `Types.AmbientFunction`.
`Abs` remains independent of value linearity. The restriction meet
represents `Mono` together with `Abs` as `MonoAbs` so both checks apply.
Legacy effect arrows still serve the active type checker. It reports a
type error for modal value annotations and uses of declared operations.

### Decisions for review

- **Combined kind spelling.** Both printers use `MonoAbs` for a
  variable restricted to absolute monotypes. The parser accepts that
  spelling, including in `Type`, `Row` and `Presence` kinds, so these
  printed types can be reused as annotations.
- **Symbolic operators.** An operator such as `<|>` or `><` stays
  intact when the parser can read it as a term operator. At a type
  boundary the parser separates adjacent modality brackets.
- **Declaration order.** Interfaces use the same lookup order as type
  aliases. An interface can refer to itself and earlier interfaces.
  Supporting mutually recursive interface declarations would require
  a separate design decision.

Fresco must expose modal prefixes hidden by aliases when it compares
types or crosses locks. Milestone 3 also applies declared restrictions
to explicit type arguments and binds range syntax to the standard pure
helper. The [baseline and milestone checks](PLAN.md#status) and
[migration inventory](MIGRATION.md) record the verified cases.

## 3. Modal inference and polymorphism

Pending implementation.

## 4. Operations, handlers and native effects

Pending implementation.

## 5. Compiler and library integration

Pending implementation.

## 6. Review and final verification

Pending implementation.
