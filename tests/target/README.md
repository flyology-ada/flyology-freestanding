# Target conformance scenarios

The files in `scenarios/` are ordinary-Ada clients of the Flyology runtime.
They deliberately exercise activation, masters, identities, stacks, delays,
protected objects, rendezvous, abort, reclamation, priorities, preemption, and
scheduling domains on the supported QEMU targets.

These packages may coordinate adversarial test timing and emit structured serial
markers, but they do not implement runtime semantics, create tasks through a
private API, choose scheduler tasks, transfer contexts, or program hardware. A
marker is emitted only after the scenario's causal assertions pass. Runtime-side
instrumentation used by a scenario remains separately identifiable and must not
become a public application API.

The current main retains the historical `Flyology_M3` unit name because the
boot/binder ABI still names `_ada_flyology_m3`. Renaming that external boundary
belongs to the platform split and remains protected by the exact-artifact
differential gate.
