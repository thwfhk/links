# SmallLinks modal effect types plan

The language design and scope are in [SPEC.md](SPEC.md#scope).
This plan records milestones, dependencies, progress and checks.
[IMPL.md](IMPL.md) will record significant implementation decisions.

Work stays on `small-met`. The design review is complete.

## Tracking

Refine the lists as implementation proceeds. Each numbered item is one
commit with its related source, tests and documentation. Split an item
before starting it if it needs several commits. Keep each commit
buildable. Tick an implementation item only when its checks pass and
record its commit ID after committing.

Follow the [implementation approach](IMPL.md#implementation-approach)
when choosing what to reuse or restructure.

## Chat handovers

Use four chats in this order:

1. Milestones 1–2: finish the design review, record the baseline, and
   implement syntax and type representation.
2. Milestone 3: implement Fresco inference and modal types.
3. Milestone 4: implement operation, handler and native-effect typing.
4. Milestones 5–6: integrate the compiler, migrate libraries and tests,
   review the combined changes and run final checks.

Each chat reads the latest SPEC.md, PLAN.md and IMPL.md before starting.
Use the same `small-met` branch and finish the preceding work before
starting the next chat's implementation. At handover, update this plan
with completed items, commits, checks, next action and blockers, and
record implementation decisions in IMPL.md.

## Milestone tracking

A milestone is complete when every item and its completion check pass.
The design review in 1.2 is required before any compiler change. During
development, new representation and checker code may be introduced
before the active compiler switches to it. The completed compiler has
one modal effect system; remove the old effect inference path once the
migration is complete.

At each pause record the milestone, next action, blockers and latest
checks under [Status](#status). Include command, source revision, result,
log path and relevant failure excerpts. Record each deferred test or
example by name and reason. Move resolved design questions into
decisions in the spec. Keep implementation decisions in IMPL.md.

## Milestones

### 1. Review the design and record the baseline

- [x] **1.1** (`3552e33f`) Read the repository guide, thesis and
  Fresco sources. Draft the syntax, typing and inference contract,
  examples, review choices, milestones and implementation framework.
- [x] **1.2** Record the approved design decisions in SPEC.md and
  update the affected checks.
- [ ] **1.3** Build and record the starting compiler, native entry points,
  regression suites and IR unit tests. Inventory effect-bearing types
  in primitives, both preludes, standard library modules and examples.
  Classify each affected fixture as a modal translation, a changed
  acceptance expectation, or a dependency on a postponed feature, using
  the criteria in [SPEC.md](SPEC.md#migration-and-deferred-coverage).
- [ ] **1.4** Add missing baseline tests for retained runtime behaviour:
  clause contexts, forwarding, shallow and parameterised resumptions,
  and value-linearity use. Separate future modal typing assertions from
  runtime assertions executable by the baseline.

Completion check: the design is approved, the baseline is reproducible,
and the required migrations and deferred features have named entries.

### 2. Update syntax and represent modal types

Depends on milestone 1.

- [ ] **2.1** Introduce `List A` and `(| |)` variant type syntax.
  Update parsers, printers, primitive signature strings,
  preludes, libraries, examples and fixtures together. Preserve term
  syntax and data-row behaviour. Check nested lists, function elements,
  open and closed variants, open record rows and print-and-reparse
  behaviour. Reserve `List`, rename existing aliases that use that name
  and preserve their tests. Reject user declarations of `List`.
- [ ] **2.2** Exclude `escape` from the first modal version with a clear
  diagnostic. Record dependent tests and examples as deferred. Keep the
  shared continuation machinery required by effect handlers.
- [ ] **2.3** Add a separate scoped effect-context representation,
  using interface identities and type arguments. Keep data-row
  unification intact. Check repeated interface instances with equal and
  different arguments, prefix subeffecting and instance order.
- [ ] **2.4** Implement modality action, composition, equivalence,
  transformations and residuals. Cover repeated masks, absent interfaces,
  interface-argument replacement, and transformations that fail despite
  equal actions at one ambient context.
- [ ] **2.5** Add effect-interface declarations and the reviewed modal
  syntax. Register member signatures and resolve operation references
  through their declarations and modules. Update source types,
  traversals, substitution, free-variable collection, kinds and both
  type printers. Cover interface arguments, modal prefixes, quantifiers
  and their combinations with list and variant types.

Completion check: the migrated list and variant syntax and the modal
type representation have focused checks. Record, variant and presence
behaviour remains covered; `escape` is identified as deferred. Printed
types parse back to equivalent types.

### 3. Implement modal inference and polymorphism

Depends on milestone 2. Keep the running compiler buildable while the
new inference path is completed with its library dependencies.

- [ ] **3.1** Introduce Fresco's bidirectional inference and checking,
  partial type information, consistency and instantiation. Reuse Links'
  unification for monotypes, data rows and presences where suitable.
  Make Fresco's control of polymorphic instantiation separate from
  monotype solving.
- [ ] **3.2** Add ambient contexts, binding contexts, locks and
  first-class modal types to the Fresco checker. Cover functions, calls,
  annotations, modal introduction and variable access. Reuse the
  reviewed SmallLinks value-restriction check. Use the standard pure
  `intRange` helper for range syntax and test shadowing. Check absolute
  kinds independently of linearity.
- [ ] **3.3** Integrate the retained explicit polymorphism forms,
  freezing, type abstraction and type application. Implement the
  reviewed generalisation rules for value, data-row and data-presence
  variables. Add rejection checks for missing modal information,
  ambiguous interface-argument/kind constraints and generalisation of
  shared interface arguments.
- [ ] **3.4** Cover recursive and mutually recursive functions, local and
  global bindings, modules and imports. Update pattern typing and the
  rules for lists, tuples, records, variants and recursive types so that
  modal dependencies survive storage, projection and matching.

Completion check: the inference examples in SPEC.md have the specified
types and annotation requirements. Tests cover both accepted and
rejected higher-rank, modal, data-row and linear cases.

### 4. Type operations, handlers and native effects

Depends on milestone 3.

- [ ] **4.1** Implement lookup of an operation's owning interface and
  its newest instance. Infer shared interface arguments and instantiate
  per-operation quantifiers separately at each call. Check absolute
  payloads and results. Reject incomplete interface handlers.
- [ ] **4.2** Implement deep handlers, input locks, modal return bindings,
  implicit returns, forwarding and multi-shot resumptions. Cover nested
  instances of one interface with different type arguments and
  enclosing-context operation and return clauses. Cover several
  complete interfaces in one handler, forwarding of other interfaces,
  explicit forwarding of members and handlers with only a return clause.
- [ ] **4.3** Implement shallow and parameterised handler rules. Preserve
  state evaluation order, resumption argument order and existing value
  usage checks. Cover dependent return values inside records and lists.
- [ ] **4.4** Implement the reviewed native permission rules. Test
  native calls under absolute annotations, recursion and ranges. Keep
  native primitive classification separate from `ApplyPure`.

Completion check: every handler and native-effect example in SPEC.md has
the specified type and result or error. Native dispatch and resumption
results agree with retained baseline runtime assertions. Mask modalities
never change operation dispatch.

### 5. Integrate the compiler and migrate the library

Depends on milestones 2–4. Prepare each runtime-library dependency before
switching the active inference path.

- [ ] **5.1** Update primitive and default-alias types, the default and
  FreezeML preludes, standard library modules and desugared helper calls.
  Translate same-context callbacks and update explicit type arguments.
  Resolve or record `Comp` and `gen0`–`gen2` dependencies.
- [ ] **5.2** Update typed frontend transformations, handler-pattern
  lowering, sugar-to-IR translation, IR type checking, substitutions and
  closure conversion. Preserve modality information until every check
  needing it has run. Keep the native runtime representation and the
  independent `ApplyPure` primitive classification. Preserve resolved
  interface and operation identities through compilation and dispatch.
- [ ] **5.3** Switch native file, expression and REPL entry points to the
  modal checker with the migrated runtime library. Remove the replaced
  effect-arrow syntax, `effectname`, effect-row inference and effect-only
  settings or coercions. Keep shared code required for data rows and
  polymorphism.
- [ ] **5.4** Migrate regression fixtures, examples and expected printed
  types. Keep original assertions where they still apply. Record each
  unavoidable deferral with its feature dependency; update example
  registration and aggregate runners together. Give the REPL handler
  fixture's `ask` its required signature while retaining its check
  across successive sentences.

Completion check: the default prelude loads; files with imports, `-e`,
REPL bindings and typecheck-only execution work. Typed frontend and IR
checks pass, and no active code relies on the old effect-row path.

### 6. Verify and document the modal language

Depends on milestone 5.

- [ ] **6.1** Independently review the combined compiler changes against
  SPEC.md and resolve findings. Check handler scopes, modal erasure,
  kind constraints and preservation of data rows and value linearity.
- [ ] **6.2** Update the SmallLinks guide to the approved syntax and
  inference rules. Turn every accepted and rejected design example into
  a registered regression and run all executable guide examples.
- [ ] **6.3** Run final build, regression, IR, source and installation
  checks on the combined revision. Record remaining deferred cases and
  their reasons. Complete this plan only when the in-scope checks pass.

Completion check: a clean CI build and temporary installation work, all
in-scope regressions and unit tests pass, printed types can be reused as
annotations, the guide matches the compiler, and deferred features have
an explicit inventory.

## Checks

1. Run `make` after compiler edits and before tests. Save full output to
   log files. Test `./links -e`, file execution with an import, a REPL
   definition and call, and `./links --set=typecheck_only=true file.links`.
2. Start handler and effect changes with
   `./test-harness tests/handlers.tests` and
   `./test-harness tests/effect_annotations.tests`. Run affected suites
   separately, preserving their applicable configuration.
3. For inference and representation changes include `polymorphism`,
   `freezeml`, `annotations`, `functions`, `mutual`, `records`, `variants`,
   `presence_type_arg`, `desugar_datatypes`, `type_print`,
   `roundtrippable_types` and `typecheck_examples`. Migrate the behaviour
   checks in `effectname` to interface declarations before retiring the
   old syntax tests.
4. For integration include `recheck_frontend_transformations`, `typed_ir`,
   `native`, `collections`, `library` and `modules`. Cases requiring
   `escape` remain in the deferred inventory.
   Run `opam exec -- ./run-tests unit-tests` for affected IR code.
5. Add focused tests for the new modality algebra and every SPEC.md
   acceptance criterion. Include the type printed for inferred values,
   shared interface arguments, wrong operation arity, interface-instance order,
   accepted pure modal introduction, rejected effectful introduction,
   modal fields and mask-only transport.
   Check forwarding of other interfaces, explicit member forwarding,
   incomplete interface rejection and operation-pattern failure
   separately. A failed pattern in a handler owning that operation must
   retain its match error; it must not forward to an outer handler.
6. Before completion run `make all-ci`, `make tests`, the IR unit tests,
   `make rule-check` and `git diff --check`. Include the example
   registration, REPL and print-and-reparse scripts. Do not repeat a
   full suite in several worktrees for an unchanged revision.
7. Since startup types and runtime files change, install to a temporary
   prefix using [INSTALL.md](../../INSTALL.md) and run
   `./tests/check-install.sh "$prefix/bin/linx"` from the repository
   root. The script checks execution outside the checkout. Test installed
   modal handler, import and polymorphism examples as well.

## Status

Milestone 1, item 1.1 is committed as `3552e33f` on `small-met`.
The user approved the remaining [design decisions](SPEC.md#design-decisions)
in 1.2.

Next action: record the implementation baseline in 1.3. The starting
compiler source revision is `e117db9da0bca9f45e9a12d2c3df808ec3880a6e`.

The deferred-case inventory will be populated in 1.3 using the criteria
in [SPEC.md](SPEC.md#migration-and-deferred-coverage).

### Design approval and `unsafe_cast` removal

Checks used `a557219f` with the approved design and removal changes.
Logs are under `/private/tmp/smalllinks-unsafe-cast.QOdUZ6/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` | Passed. | `build.log` |
| `./links -e 'unsafe_cast(42)'` | Rejected with `Unknown variable unsafe_cast.` | `removed.log` |
| `./test-harness tests/native.tests` | 71 passed, including the removal regression. | `native.log` |
| `./test-harness tests/handlers.tests` | 107 passed. | `handlers.log` |
| `./test-harness tests/effect_annotations.tests` | 18 passed. | `effect-annotations.log` |
| `./test-harness tests/typecheck_examples.tests` | 35 passed. | `typecheck-examples.log` |
| `./links examples/extensible-case.links` | Returned `("A", "B", "C")`. | `extensible-case.log` |
| `make rule-check` | Passed. GNU find was unavailable for the tabs rule. The same file patterns passed with `rg`. | `rule-check.log`, `tabs.log` |
| `git diff --check` | Passed. | `diff-check.log` |

### Initial design checks

The initial draft received separate read-only reviews against the thesis,
Fresco sources and SmallLinks implementation. Corrections to locks,
generalisation, kind restrictions, syntax and native effects are
included.

Checks on 14 November 2026 used
`e117db9da0bca9f45e9a12d2c3df808ec3880a6e` plus these documents.
Logs and extracted snippets are under
`/private/tmp/smalllinks-met-design.EcMuxo/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `make` | Passed on the unchanged compiler source. | `build.log` |
| `make rule-check` | Passed. GNU find was unavailable for the tabs rule; the same file patterns passed with `rg`. | `rule-check.log`, `tabs.log` |
| `git diff --check` and `git diff --no-index --check /dev/null` for each new document | No whitespace diagnostics. | `diff-check.log`, `documents.log` |
| Check local document links, source-reference paths, code fences and document whitespace | Passed. | `documents.log` |

### Initial draft examples run with the current compiler

During the initial drafting, all 20 fenced Links snippets were extracted
from SPEC.md into temporary files, with preceding definitions supplied
where needed. These files preserve the examples before the subsequent
syntax changes and deferral of `escape`. They were checked with
`./links --set=typecheck_only=true` using
the existing row-based compiler at the revision above. The accepted
snippets were then run with `./links`.

| Snippets | Result and cause | Log |
| --- | --- | --- |
| Seven using supported syntax | Accepted and returned the documented values: `(42, true)`, `42`, `1`, `42`, `[1, 2]`, `42`, `42`. | `example-02.log`, `example-03.log`, `example-08.log`, `example-12.log`, `example-14.log` through `example-16.log` |
| One deliberately ill-typed example | Rejected as intended: `do Ask + 1` requires an `Int` result, while the handler resumes with `true`, requiring `Bool`. | `example-09.log` |
| Twelve using proposed modal syntax | The current parser rejected unsupported forms such as `[Ask:() => Int]` and `a::Abs`. Modal checking for these examples is pending implementation. | `example-01.log`, `example-04.log` through `example-07.log`, `example-10.log`, `example-11.log`, `example-13.log`, `example-17.log` through `example-20.log` |

`examples.json` lists every command result. The parse errors came from
passing the proposed syntax to the current compiler. Modal acceptance
tests will be added in milestones 3–6.

The full implementation baseline in 1.3, modal acceptance tests and
final combined checks remain pending.

### Follow-up checks

These checks used the same source revision and existing baseline
executable, with the revised documents. Logs are under
`/private/tmp/smalllinks-met-review2-w4r6hp65/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `./links` on runtime counterparts of the revised conditional, native-call, list and variant examples, using current type annotations | All four passed: `42`, printed `hello` and returned `()`, `[20, 22]`, and `42`. The proposed type syntax remains pending implementation. | `runtime-checks.json`, `conditional.log`, `native.log`, `list.log`, `variant.log` |
| `./links --set=typecheck_only=true` on the variant payload mismatch using the current variant syntax | Rejected as expected: `Just(true)` cannot have an `Int` payload. | `variant-rejection.log` |
| `./links -e` with a replacement `intRange` that prints before returning `[42]`, followed by `[1..3]` | Printed `shadowed[42] : [Int]`. This confirms the helper-lookup issue in [Value restriction](SPEC.md#value-restriction). | `range-shadowing.log` |
| Check document links, code fences, table columns and whitespace; `git diff --check` | Passed. | `documents.log`, `diff-check.log` |

### Effect-interface review checks

R1–R6 decisions and the converted examples were reviewed against the
thesis and Fresco sources. The checks used
`e117db9da0bca9f45e9a12d2c3df808ec3880a6e` and the updated documents.
Logs are under `/private/tmp/smalllinks-met-decisions-6z_udikx/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `./links` on the two new accepted handler bodies in example 15, without the proposed interface declarations | Both returned `42 : Int`. | `mixed-interfaces.log`, `explicit-forwarding.log` |
| Check document links, reference paths, code fences, table columns and whitespace | Passed. | `documents.log` |
| Check that modal contexts use interface names, and inspect the changes from the previous draft | Passed. | `documents.log`, `SPEC.md.diff`, `PLAN.md.diff` |
| `git diff --check` | Passed. | `diff-check.log` |

Interface declarations, their type checks and incomplete-interface
rejections remain implementation checks for milestones 2–4.

### R7 syntax checks

These checks used `e117db9da0bca9f45e9a12d2c3df808ec3880a6e` and
the revised documents. Logs are under
`/private/tmp/smalllinks-met-r7-i0m_lbp4/`.

| Command or check | Result | Log |
| --- | --- | --- |
| `./links` on the annotated variant example with the current compiler's delimiters | Returned `42 : Int`. | `variant.log` |
| `./links --set=typecheck_only=true` on its `Just(true)` variant | Rejected as expected because the declared payload is `Int`. | `variant-payload-rejection.log` |
| Check the proposed delimiters against the existing variant-row grammar; check document links, fences, tables and whitespace | Passed. The new delimiters and reserved `List` rule await compiler implementation. | `documents.log` |
| `git diff --check` | Passed. | `diff-check.log` |
