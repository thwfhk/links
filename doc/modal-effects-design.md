# Modal effects design

## Status and scope

This document will record the design for modal effect types in Links.
The source comparison and technical decisions are pending. Track
implementation tasks, progress, and verification in [PLAN.md](../PLAN.md).
Follow [AGENTS.md](../AGENTS.md) for repository conventions.

Database support, control-flow linearity, and session failure are out
of scope for now.

## Sources to examine

- Wenhao's thesis, including modal effects and Fresco type inference:
  `~/code/latex/phd-thesis`.
- Aghilas' implementation of modal effects with Fresco:
  `~/code/type/frost/paper/artifact/freso-implementation`.
- Aghilas' implementation with DK-style bidirectional type inference:
  `~/code/algebraic-effects/aghilas-met-impl`.
- Links syntax and parsing: `core/sugartypes.ml`, `core/lexer.mll`,
  and `core/parser.mly`.
- Links types and inference: `core/types.ml`, `core/typeSugar.ml`,
  `core/unify.ml`, `core/generalise.ml`, and `core/instantiate.ml`.
- Links effect processing: `core/desugarEffects.ml`,
  `core/desugarTypeVariables.ml`, and `core/sugartoir.ml`.
- Existing examples and tests in `examples/handlers/` and `tests/`.

Repository paths above are relative to the Links repository root.
As sources are examined, record the file paths, sections, and relevant
definitions supporting each design choice.

## Open questions

1. Which version of the modal effect system will this branch implement?
   Identify its constructs, typing rules, and required examples.
2. Is Fresco part of this implementation? Compare adapting Links'
   current inference with the two reference implementations.
3. How will modal types and effect information be represented in Links?
   Identify the required changes to contexts, unification,
   generalisation, and instantiation.
4. What syntax and type annotations will programs use? Which existing
   effect syntax and programs should remain supported?
5. Which interactions with polymorphism, recursion, records, variants,
   and modules belong in the first implementation?
6. Can the agreed constructs use the existing effect-handler runtime?
   Identify any required changes to compilation or evaluation, and
   decide whether JavaScript execution belongs in the first milestone.

## Source comparison

Pending. Compare the typing rules and inference algorithms in the
references with Links' current implementation. Record both reusable
parts and differences that require changes.

## Types, syntax, and typing rules

Pending. Define the chosen types, term constructs, contexts, and
typing rules. State the relationship to existing Links effect rows
and effect handlers, including any intended changes to accepted
programs. Link each rule to its source.

## Type inference

Pending. Record the chosen inference approach, required annotations,
and treatment of unknown type variables, unification, generalisation,
and instantiation. Explain how the algorithm follows the chosen rules.

## Implementation in Links

Pending. Map each agreed construct and rule to the affected data
types, functions, and compiler passes. Describe how typed programs
reach the existing intermediate representation and runtime, and
identify any required runtime changes.

## Examples and expected behaviour

Pending. Add a small set of accepted and rejected programs. For each
example, record the rule it exercises and its expected type, result,
or reason for rejection. Identify the first example to implement and
link examples to their tests as those tests are added.

## Design decisions

No technical design has been selected yet. Record each decision with
its date, chosen approach, reason, supporting source or example, and
consequences for implementation. Mark proposals and agreed decisions
clearly. Keep unresolved choices in the open questions above.
