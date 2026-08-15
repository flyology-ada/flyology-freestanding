# Clean-room interface evidence

This directory records the provenance and supported semantics of every
compiler-facing runtime interface without consulting or reproducing GNAT runtime
implementation source.

- [Methodology](methodology.md) is the normative discovery, implementation, and
  upgrade procedure.
- [Interface manifest](interfaces.toml) is the machine-readable evidence index.
- [Bootstrap minimum](bootstrap-minimum-compiler-interface.md) records the
  minimal package `System` boundary.
- [Bootstrap elaboration](bootstrap-elaboration-interface.md) records binder
  and diagnostic bootstrap shape.
- [Tasking](tasking-compiler-interface.md) records ordinary task activation, masters,
  placement, identity, and completion.
- [Synchronization](synchronization-compiler-interface.md) records synchronization, delay, priority,
  exception, abort, dynamic-task, and finalization surfaces.
- [Preemption](preemption-policy-interface.md) records standard
  dispatching-policy lowering.
- [Dispatching domains](dispatching-domain-interface.md) records standard
  dispatching-domain lowering.

The records preserve when and how evidence was discovered, but are indexed by
the capability they support. ADR-0004 and ADR-0006 define the clean-room
decision; ADR-0010 defines the responsibility-based product migration.
