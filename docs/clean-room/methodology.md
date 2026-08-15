# Clean-room interface methodology

This document is the normative engineering procedure for discovering and
maintaining compiler-facing interfaces. It implements ADR-0004 and ADR-0006. It
is not legal advice or a warranty about third-party intellectual property.

## Separation rule

Flyology runtime implementation work may use only:

- the Ada Reference Manual and published Ada Issues;
- public compiler user/reference documentation;
- compiler-generated expansion, binder output, ALI metadata, representation
  reports, symbol tables, relocations, and disassembly from Flyology-owned probes;
- compiler and linker diagnostics elicited by those probes; and
- black-box language behavior tests written from the specification.

GNAT runtime source, comments, bodies, tests, and internal design documentation
are not implementation inputs. GCC source archives listed in
`docs/external-inputs.md` are provenance-only inputs and must not be opened to
answer a runtime design question. If permitted evidence cannot establish a
required interface or semantic, the implementation records an unsupported or
fail-closed boundary instead of guessing or importing code.

## Evidence unit

Every supported compiler-facing interface set has an entry in
`docs/clean-room/interfaces.toml`. The entry records:

- a stable evidence identifier;
- the exact compiler family and supported target architectures;
- the human-readable observation record;
- the owned probe or authoritative discovery gate;
- the implementation root and an exact tracked inventory of implementation
  units participating in the boundary;
- the regression gate that enforces the observation; and
- a semantic status: `supported`, `bounded`, `fail_closed`, or `historical`.

An interface record must distinguish four different claims:

1. **shape** — name, profile, representation, convention, or call order observed
   in generated artifacts;
2. **implementation** — original Flyology code accepts that boundary;
3. **semantics** — behavior demonstrated by target/black-box tests; and
4. **proof** — deterministic kernels proved by SPARK or explored by a model.

Evidence for one claim is not evidence for the others. In particular, a symbol
in an object file does not prove language semantics, a passing QEMU marker does
not prove the concurrent wrapper, and a SPARK model does not prove assembly or a
foreign ABI unless a separately checked refinement boundary exists.

## Probe discipline

Each new compiler-facing entity is introduced in this order:

1. Write the smallest owned source that forces the entity.
2. Compile it for both pinned cross targets with no installed target runtime.
3. Capture normalized expansion, ALI, undefined-symbol, relocation,
   representation, and disassembly evidence that is relevant to the boundary.
4. Vary or subtract declarations to establish necessity and reject guessed
   fields or operations.
5. Record the exact tools, versions, digests, commands, observed shape, and
   target differences.
6. Implement the smallest original boundary and delegate semantics downward.
7. Add structural inspection and ordinary-Ada behavioral gates.
8. Add or update the manifest entry and cite its evidence identifier from the
   implementation-facing documentation.

Generated probe output stays under ignored build directories. Owned probe
sources, normalization/check scripts, expected inventory, and concise findings
are tracked. Reproducible hashes may cover normalized output; raw addresses,
timestamps, temporary paths, and target-specific noise must not be accepted as
semantic evidence.

## Product project boundary

`gpr/flyology_image.gpr` is the authoritative Ada compilation graph for both
freestanding conformance images and independent application images. Its source
directories make compiler-facing units discoverable, but directory membership
is not clean-room evidence and does not enlarge any interface claim. The exact
implementation inventory named by each manifest entry remains authoritative
for that claim.

The generated original-work `Flyology_Launcher` is the binder main and invokes
the selected ordinary-Ada application procedure after requiring the RTS
elaboration closure. The project also roots the runtime/binder authorities and
the two Flyology validation bodies exported to platform entry assembly. Every
compiler facade and remaining semantic implementation object is selected
through an Ada dependency from those roots and the chosen configuration view.
The separate `gpr/flyology_cross.cgpr` describes only the no-installed-runtime
compiler protocol; it supplies no GNAT runtime sources, libraries, or semantic
behavior. Concrete tool paths come from the pinned Alire workspaces and are not
recorded as source inputs.

Application procedures, the launcher template, the console API, UEFI bundle
layout, and QEMU command are not compiler-facing GNARL interfaces. They remain
outside the clean-room interface manifest and cannot be cited as compiler-shape
evidence.

## Compiler upgrades

A compiler upgrade creates a new evidence baseline. It requires:

- new exact tool version and artifact digests;
- a complete two-target probe rerun;
- reviewed diffs of normalized expansion, binder, ALI, symbol, relocation, and
  representation evidence;
- a fresh final-ELF interface inventory;
- the full ordinary-Ada target matrix; and
- a review entry stating which shapes changed and why the implementation remains
  compatible.

Silently accepting a new compiler because source files still compile is not an
upgrade gate.

## Repository checks

`scripts/check-clean-room.sh` validates the manifest schema at repository
hygiene time: identifiers are unique, statuses are from the closed vocabulary,
every referenced record, probe, implementation root, inventory, and gate
exists, and every non-comment path in an implementation inventory resolves to a
tracked source file. The inventories prevent a broad directory reference from
silently expanding a clean-room claim when an unrelated compiler facade is
added. Generated symbol/relocation inventories remain enforced by the cited
probe and final-image inspection scripts.

`scripts/check-product-project.sh` independently verifies that every supported
profile names the same target project and compiler configuration, and rejects a
second procedural Ada source graph in the image shell builder. This is a build
ownership check, not compiler-interface evidence or a semantic proof.
