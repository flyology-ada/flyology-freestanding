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

The scenario main is `Flyology_Conformance`; its binder symbol is private to the
test image and is checked alongside the platform entry that invokes it.

`config/domains/on` and `config/domains/off` provide the conformance profile
that either invokes or omits the domain scenario. The hook is test composition,
not domain-runtime semantics; product domain configuration remains separate.
