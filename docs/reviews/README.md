# Capability reviews

Each capability review is written after its gates run and contains:

- exact commit, tool versions, commands, targets, CPU counts, and artifact hashes;
- cited code, tests, proof outputs, and diagnostic transcripts;
- findings by blocker/high/medium/low severity;
- explicit coverage of architecture, hardware, Ada/GNARL semantics, SMP/atomics, interrupt/ABI state, scheduler boundaries, memory/lifecycle, SPARK soundness, security, diagnostics, portability claims, and subtraction;
- fixes and rerun evidence for every blocker; and
- a candid residual-risk and unsupported-claims section.

A review template is not evidence and does not close a capability.

The responsibility-based repository/product closure is recorded separately in
[product-structure.md](product-structure.md); it composes but does not broaden
the individual capability reviews.
