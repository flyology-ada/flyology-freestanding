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

`formal/tla/SchedulingDomains.tla` explores creation of one secondary domain
from a nonempty subset of the four-core system domain, explicit and inherited
task admission, specific and automatic CPU placement, dispatch, atomic
global/domain/core live-policy replacement, and bounded round-robin rotation.
Its invariants require one immutable domain owner per core, nonempty
system-domain membership, unique ready/current ownership, queue/current
isolation to the task's domain and home core, valid effective per-core policy,
and zero FIFO rotation. Domain changes replace member-core overrides, global
changes replace every override, and core changes preserve their domain
default. Terminal configurations are valid bounded scenarios, so deadlock
checking is disabled for this model.

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
| Scheduling-domain isolation and live policy | 17,035,809 | 683,040 | terminal states allowed |
| Wait arbitration | 5,839 | 1,513 | terminal states allowed |

Run `scripts/test-tla-models.sh`. It requires the ignored external
`downloads/tla2tools-1.8.0.jar` and the pinned OpenJDK 21 binary recorded in
`docs/external-inputs.md`. The tool is external MIT-licensed material and is not
linked into or shipped with the runtime. `scripts/verify-formal-models.sh`
combines this exploration with GNATprove and all bounded Ada host models; dispatching-domain capability and
later milestone gates must invoke that aggregate before their target runs.
