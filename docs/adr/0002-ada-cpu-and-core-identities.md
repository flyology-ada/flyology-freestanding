# ADR-0002: Map Ada CPU numbers explicitly to dense core identities

- Status: accepted
- Date: 2026-08-12

## Context

Ada's task dispatching model reserves CPU value zero for `Not_A_Specific_CPU` and numbers specific CPUs from one. Flyology's internal `Core_Id` is deliberately dense from zero. Firmware and interrupt-controller identities are neither Ada CPU numbers nor guaranteed dense.

## Decision

Maintain four distinct representations:

- `Core_Id` in `0 .. CPU_Count - 1` for internal array indexing;
- Ada CPU numbers in `1 .. CPU_Count`, with zero retaining `Not_A_Specific_CPU` meaning;
- Limine `processor_id`; and
- x86 LAPIC/x2APIC ID or AArch64 MPIDR.

Validated conversion between a specific Ada CPU and `Core_Id` is `Core_Id (CPU - 1)` in the forward direction and `CPU (Core + 1)` in the reverse direction. These conversions are implemented in a SPARK topology kernel with range, capacity, uniqueness, and BSP checks. Hardware identities are mapped by searched/validated topology records, never arithmetic casts.

## Consequences

Public Ada aspects retain their standard meaning without compromising dense internal storage. Every scheduling-domain admission check receives a validated `Core_Id`; boot protocol and interrupt code retain the hardware identity needed by their architecture.
