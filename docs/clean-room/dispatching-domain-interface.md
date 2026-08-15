# dispatching-domain capability dispatching-domain interface record

This record derives the public surface from Ada 2022 RM D.16/D.16.1 and the
compiler boundary from Flyology-owned sources expanded by both pinned GNAT 15.3
cross compilers. No GNAT run-time source was consulted.

The owned `probes/domains/domain_probe.adb` declares one task with only the standard
`Dispatching_Domain` aspect and one task with both `Dispatching_Domain` and
`CPU`. `scripts/probe-domain-interface.sh` compiles it with `-nostdinc`, the owned
ARM-shaped predefined units, `-gnatG`, and both target compilers. The normalized
undefined surfaces agree.

The generated task value record gains a field of exact type
`System.Tasking.Dispatching_Domain_Access`. Its initializer converts the
limited domain object directly to that access type. Disassembly of the owned
probe shows that this conversion reads the first machine word of the public
domain object; it does not take the public object's address. Flyology therefore
places a stable, runtime-owned `System.Tasking.Dispatching_Domain_Access` handle
at byte offset zero. The remaining compiler-visible layout is `First` at byte
8, `Last` at byte 12, and the Flyology identifier at byte 16, for a total size
of 192 bits and alignment 8. `scripts/probe-domain-interface.sh` obtains and checks
that representation report with both pinned target compilers.

The compiler passes that first-word handle as the seventh argument of the
already established `System.Tasking.Stages.Create_Task` profile. A task without
the aspect passes null, which means inherit the activator's immutable domain.
Every explicit domain, including `System_Dispatching_Domain`, consequently has
a distinct stable non-null handle registered with the runtime. This distinction
is required when a secondary-domain task explicitly creates a child in the
system domain. A simultaneous `CPU` aspect still stores the 1-based
`System.Multiprocessors.CPU_Range` value separately and passes its `Integer`
conversion. Activation fails without partial publication if that CPU is outside
the selected domain's CPU set.

The language `Create` returning limited `Dispatching_Domain` is lowered with a
compiler-generated build-in-place result access parameter. This is generated
Ada ABI, not a Flyology-designed calling convention. Implementing the
ARM-shaped limited return in Ada lets the same compiler generate the exact
target ABI; no assembly or C adapter is required.

dispatching-domain capability retains the Ada 2022 public package shape, including range and `CPU_Set`
creation, domain/CPU queries, assignment operations, and
`Delay_Until_And_Set_CPU`. The bounded product capability closes only immutable initial
membership through task aspects and inheritance. Cross-domain reassignment is
explicitly unsupported under ADR-0003 and must raise the language domain error
rather than partially transferring ready, timer, protected-action, or context
ownership. The presence of a declaration or compiler symbol is not a claim that
all dynamic semantics are implemented.

The compiler-generated `CPU_Set` query uses a secondary-stack return. The dispatching-domain capability
image therefore retains the previously discovered secondary-stack compiler
boundary and supplies bounded per-execution-slot 1 KiB areas. Marks, releases,
alignment, capacity, and arithmetic are checked; exhaustion raises
`Storage_Error`. This is a compiler ABI service, not a second task stack or an
allocator/reclamation claim.

The first bounded product configuration creates one secondary domain over Ada
CPUs 3 and 4, leaving CPUs 1 and 2 in the system domain. The system domain uses
FIFO-within-priorities and the secondary domain uses round robin. That policy
mapping is the initial runtime configuration; applications still create and
assign tasks only through the standard Ada domain type and task aspect. The
original `Flyology.Scheduling` extension may later replace a domain's default
and effective per-core policies without changing membership or placement.
The ordinary-Ada gate checks both implicit inheritance into the secondary
domain and an explicit `System_Dispatching_Domain` override by a child whose
activator belongs to that secondary domain.

Reference: Ada 2022 RM D.16 and D.16.1, as published by the Ada Rapporteur
Group and Ada Resource Association.

## Verification boundary

The authoritative dispatching-domain capability gate combines three deliberately different kinds of
evidence. GNATprove proves the deterministic domain transition kernel and its
exact frame conditions. The bounded Ada host model checks representative
creation and admission sequences. TLC explores domain creation, inheritance,
specific and automatic placement, dispatch, global/domain/core live-policy
replacement, and round-robin rotation across 683,040 distinct states. None of
those checks proves concurrent `Flyology.Kernel`,
compiler-facing facade, secondary-stack implementation, architecture context
handoff, or hardware. Those boundaries are instead checked by both-target
compiler probes, ELF/layout inspection, and bounded QEMU execution.

During target stress, two architecture-boundary defects were exposed that the
deterministic models intentionally do not represent. First, the preemption capability diagnostic
canary used a per-core active flag even though interrupt-time preemption can run
a different task on that core; validating the replacement task against the
interrupted task's canary constants produced a false fatal. The pre-Ada canary
remains in the interrupt-substrate checkpoint no-transfer profile, while preemption capability/dispatching-domain capability rely on the task-local
post-resume complete-context check. Second, interrupt-frame validation rejected
an initial task stack pointer equal to the exclusive top of its allocated
extent before the task trampoline's first push. Interrupt validation now
accepts that one legal boundary value while ordinary live-stack probes remain
strictly inside the extent. A 100-run focused x86-64 SMP4 diagnostic campaign
passed after the fixes; the authoritative gate then reran the complete bounded
matrix on both architectures.
