# Executable formal models

Flyology uses TLA+ as an early concurrency-design check alongside SPARK and the
bounded host models. The specifications are original design models; they are
not derived from GNAT run-time source.

`formal/tla/SchedulerPreemption.tla` explores global RTS-lock ownership,
nonblocking interrupt ingress, retained request/retry state, FIFO head versus
round-robin tail preemption, complete-context ownership, dispatch, yield, and
Ready-task priority tail requeue. Its invariants reject duplicate ready/current
ownership, lost retry requests, and saved continuations outside the ready set.
TLC's deadlock check remains enabled for this model.

`formal/tla/WaitArbitration.tla` explores every ordering of arm, commit,
normal wake, timeout, abort, stale-generation rejection, and dispatch for two
tasks and two wait generations. It checks an explicit at-most-one winner count,
single ready membership, complete registration while pending, and removal of
every losing registration after one winner. Its bounded terminal states are
valid completed scenarios, so this model disables deadlock checking and makes
only the listed safety claim.

These models deliberately do not claim source-code refinement or proof of the
Ada, C, assembly, atomics, compiler ABI, or hardware. Each retained algorithm
must still have a typed production boundary, SPARK contracts where applicable,
host/model correspondence tests, and target execution gates. When a concurrency
design changes, update the TLA+ transition first or in the same commit, obtain a
counterexample-free bounded run, then update the implementation and its direct
tests. Pinned generated/distinct state counts make accidental exploration shrink
fail closed.

The current exact bounds are:

| Model | Generated states | Distinct states | Deadlock claim |
| --- | ---: | ---: | --- |
| FIFO scheduler/preemption | 1,171,969 | 165,888 | checked |
| Round-robin scheduler/preemption | 1,202,689 | 165,888 | checked |
| Wait arbitration | 5,839 | 1,513 | terminal states allowed |

Run `scripts/test-tla-models.sh`. It requires the ignored external
`downloads/tla2tools-1.8.0.jar` and the pinned OpenJDK 21 binary recorded in
`docs/external-inputs.md`. The tool is external MIT-licensed material and is not
linked into or shipped with the runtime. `scripts/verify-formal-models.sh`
combines this exploration with GNATprove and all bounded Ada host models; M6 and
later milestone gates must invoke that aggregate before their target runs.
