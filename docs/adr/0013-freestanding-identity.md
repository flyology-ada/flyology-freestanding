# ADR-0013: Name the product and namespace Flyology Freestanding

- Status: accepted
- Date: 2026-08-15

## Context

The project began as a sequence of runtime experiments under the name
Flyology Barebones and used `Flyology` as its Ada root package. A separate
Flyology application/core library also owns that natural root. Alire can
resolve two distinct crate names, but Ada compilation cannot combine two
different library roots with the same unit name. Generic `flyology_*` linker
symbols and `FLYOLOGY_*` build variables create the same collision at later
integration boundaries.

"Barebones" also describes an early implementation state rather than a stable
technical contract. The runtime is deliberately small, but it is not intended
to remain skeletal. "Freestanding" states the durable property: the runtime
does not depend on a hosted operating-system runtime.

## Decision

The product and intended repository are named **Flyology Freestanding**. The
Alire crate is `flyology_freestanding`, and its Ada root is
`Flyology_Freestanding`. Flyology-owned build variables and linker symbols use
`FLYOLOGY_FREESTANDING_*` and `flyology_freestanding_*`. Consumer tools and
deployable artifacts use the human-facing `flyology-freestanding-*` spelling.

This is a hard migration. The crate provides no forwarding `Flyology` package,
old Alire crate alias, duplicate build variable, or linker compatibility shim.
Keeping either namespace would preserve the exact ambiguity the rename is
intended to remove.

Compiler-mandated names do not change. Predefined `Ada.*` and `System.*` units,
`__gnat_*` hooks, binder globals, entry symbols required by firmware, and the
internal `Ada.Task_Identification.Flyology` bridge retain their discovered
compiler-facing spellings. The latter is a child below a language-defined
package, not the product's Ada root.

## Consequences

A consumer may depend on `flyology_freestanding` alongside another Flyology
crate and explicitly import `Flyology_Freestanding.Console`,
`Flyology_Freestanding.Scheduling`, or later application APIs without an Ada
root collision. Generated binder output, assembly/C references, GPR projects,
proof projects, clean-room inventories, examples, and artifact paths all use
one coherent identity.

Existing consumers must update their dependency name, package imports,
environment variables, runner/build-tool references, and artifact names in one
change. This is intentional while the crate is still `0.1.0-dev`; no released
compatibility contract is being withdrawn. Renaming the remote repository to
`flyology-freestanding` is an external hosting operation and is not performed
by this source-tree decision.
