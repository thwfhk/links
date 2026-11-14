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

The design review is complete. The baseline inventory is pending.

Removed `unsafe_cast` from the native primitive table in `core/lib.ml`.
Checked upcasts use IR coercions. `tests/native.tests` checks that the
primitive is unavailable.

## 2. Syntax, types and scoped contexts

Pending implementation.

## 3. Modal inference and polymorphism

Pending implementation.

## 4. Operations, handlers and native effects

Pending implementation.

## 5. Compiler and library integration

Pending implementation.

## 6. Review and final verification

Pending implementation.
