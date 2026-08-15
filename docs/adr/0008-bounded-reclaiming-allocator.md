# ADR 0008: Reclaim compiler heap objects under the RTS critical section

- Status: accepted
- Date: 2026-08-14

## Context

GNAT lowers ordinary access-type allocation and `Ada.Unchecked_Deallocation`
to `__gnat_malloc` and `__gnat_free`. The first synchronization capability checkpoint used a safe
monotonic 64-KiB cursor, which proved exhaustion arithmetic but could not reuse
heap objects after task execution slots and stacks had been retired. Adding a
second allocator spinlock would also create a new mutation authority and would
be unsafe once interrupt-time task preemption is enabled.

## Decision

Keep one statically bounded 64-KiB pool split into 4,096 16-byte allocation
units. Allocation scans the occupancy map in address order and reserves the
first complete free run. Side metadata stores the unit count only at the exact
head; release validates pool extent, alignment, head ownership, every occupied
unit, live-count arithmetic, and interior metadata before clearing the run.
Null release is harmless. Interior, stale, duplicate, and foreign pointers fail
closed without mutating the map.

All allocator metadata changes occur under the existing recursive RTS critical
section. No allocator-owned lock, task-state authority, or public allocation
API is introduced. The compiler-facing surface remains only the observed
`malloc`, `free`, `__gnat_malloc`, and `__gnat_free` symbols. Stable Ada
`Task_Id` tombstones, reusable execution slots/stacks, and reclaimable heap
objects remain separate lifetimes.

SPARK proves alignment/capacity arithmetic, first-fit minimality, exact range
marking, and matching range restoration in a bounded state model. The C ABI and
concurrent metadata mutation remain outside SPARK and are checked by the exact-
source native concurrency/reuse gate plus both target QEMU images.

## Consequences

Fragmentation can reject a large allocation even when total free space is
sufficient; this is a deterministic bounded allocator, not a virtual-memory
manager. Scanning 4,096 units under the global lock is acceptable for the
current small synchronization capability pool but must be reconsidered before substantially increasing
capacity. General controlled-object finalization races and storage-pool
customization remain separate GNARL/Ada semantics rather than allocator
metadata concerns.
