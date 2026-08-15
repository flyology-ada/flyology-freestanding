# ADR-0003: Name scheduling semantics precisely and keep dispatching-domain capability domains immutable

- Status: accepted
- Date: 2026-08-12

## Context

Ada's `FIFO_Within_Priorities` is preemptive when a higher-priority task becomes ready; it merely lacks same-priority time slicing. Calling a globally cooperative scheduler “standard non-preemptive FIFO” would misstate Ada semantics. Separately, the dispatching-domain capability requirement fixes initial scheduling-domain membership, while the standard domain surface includes reassignment operations whose complete semantics would require cross-domain ownership transfer.

## Decision

The standard-aligned FIFO configuration implements higher-priority preemption and no equal-priority quantum. The preemptive time-sliced configuration implements `Round_Robin_Within_Priorities`. A globally cooperative policy, if retained for a heterogeneous demonstration, is explicitly named a Flyology Freestanding extension and is not described as standard FIFO semantics.

Domain membership is immutable through dispatching-domain capability. Admission occurs before activation and checks task, requested Ada CPU, and eligible core set. Standard reassignment operations that would move an activated task across domains fail with a documented unsupported-operation diagnostic; Flyology Freestanding does not claim complete `Assign_Task` support in dispatching-domain capability.

## Consequences

The runtime can demonstrate heterogeneous policy instances without blurring standard dispatching semantics. Cross-domain migration remains deferred until priority interpretation, pending timers, blocked entries, protected actions, and ownership transfer have an explicit model.
