# ADR 0007: Pin the QEMU monotonic-clock and local-timer contract

- Status: accepted
- Date: 2026-08-13

## Context

Ada delays, timed entry calls, and scheduling quanta need one monotonic tick
domain and one timer per core. The initial release is deliberately scoped to
the fixed QEMU machines, so broad discovery and physical-server claims would
add mechanisms without evidence. Timer interrupts must not mutate Ada wait
queues or switch contexts while the global RTS lock may be held.

## Decision

The x86-64 test contract adds `tsc-frequency=1000000000` to QEMU's pinned
`-cpu max` model. The runtime reads TSC with `lfence; rdtsc; lfence` and
calibrates each core's x2APIC divide-by-16 one-shot timer against that clock.
It rejects zero or implausible calibration rates and clamps long arms to the
32-bit initial-count horizon. No invariant-TSC or physical-machine claim is
made.

AArch64 uses `CNTVCT_EL0`, validates the nonzero `CNTFRQ_EL0` value through the
typed Ada boundary, and programs absolute `CNTV_CVAL_EL0` deadlines on virtual
timer PPI 27. Both architectures disable the local timer when no deadline is
registered.

Nanosecond conversion, checked deadline addition, timer-table membership, and
single-winner timeout arbitration are SPARK kernels. Interrupt handlers only
disable/acknowledge the local timer and release-publish a timer request epoch.
The owning core drains due exact tokens under the RTS lock at a dispatcher
boundary, reprograms its own timer, and resumes winners through the common task
state authority. synchronization capability therefore provides timed blocking but not arbitrary
instruction preemption; preemption capability will connect complete interrupt frames to dispatch.

## Consequences

Ordinary Ada `delay` statements can be tested across both pinned QEMU machines
without a general clock-device discovery layer. Remote deadline changes will
need a timer-reprogram request and IPI/SGI before timed synchronization is
complete. A later ACPI/DTB or physical-server port must replace this ADR with
validated clock frequency, synchronization, skew, and timer geometry.
