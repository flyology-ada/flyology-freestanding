# Clean-room interface evidence

This directory records the provenance and supported semantics of every
compiler-facing runtime interface without consulting or reproducing GNAT runtime
implementation source.

- [Methodology](methodology.md) is the normative discovery, implementation, and
  upgrade procedure.
- [Interface manifest](interfaces.toml) is the machine-readable evidence index.
- [M0](m0-compiler-interface.md) records the minimal package `System` boundary.
- [M1](m1-compiler-interface.md) records binder and diagnostic bootstrap shape.
- [M3](m3-tasking-interface.md) records ordinary task activation, masters,
  placement, identity, and completion.
- [M4](m4-compiler-interface.md) records synchronization, delay, priority,
  exception, abort, dynamic-task, and finalization surfaces.
- [M5](m5-policy-interface.md) records standard dispatching-policy lowering.
- [M6](m6-domain-interface.md) records standard dispatching-domain lowering.

The milestone labels identify when evidence was discovered; they are historical
record keys, not the product architecture. As the repository is productized,
records may gain capability aliases but their original observations remain
immutable. ADR-0004 and ADR-0006 define the clean-room decision; ADR-0010 defines
the responsibility-based product migration.
