# Allocator Ada migration review

## Status

Complete for reviewed source tree
`0191af02c5b19e17a1c9469ee2b38762acc7d880`. The eventual commit adds this
review record and proof-scope wording corrections only; no implementation,
build, or gate source changed after the authoritative evidence was produced
from that exact staged tree.

The bounded compiler allocator is now Ada end to end. The deterministic
first-fit state engine is `Flyology_Freestanding.Allocator` in the primitive library, and
the narrow `Flyology_Freestanding.Allocator_ABI` facade owns the aligned byte pool, RTS-lock
serialization, checked address conversion, and the four compiler-facing C
convention exports. The previous allocator C source and both C-only test
adapters were removed. The sole remaining production C file is the 744-line
exception personality/generic-unwinder bridge in `src/abi/exception_runtime.c`.

## Review findings and dispositions

- The first proof run could not establish two allocator index bounds. The
  production transition now validates the discovered extent before indexing it;
  no assumption, disabled check, or reduced proof scope was introduced.
- An early draft coupled the minimal compiler-interface exception probe to the
  product allocator facade. The probe was restored to its owned minimal source,
  while the exception image project retains the allocator facade explicitly.
- The unwind checker assumed one task-root relocation on both targets. The
  pinned x86 compiler emits two relocations for the weak-symbol availability and
  region comparison, while AArch64 folds the expression into one. The gate now
  pins both exact shapes and still requires one frame registration plus FDEs for
  `__gnat_malloc` and `__gnat_free`.
- A separate allocator run-time initializer caused an early freestanding
  elaboration failure and added no invariant unavailable from static Ada
  representation and default initialization. It was subtracted. The final pool
  is intentionally uninitialized, as `malloc` storage should be; metadata has a
  static empty-state representation, and every mutation validates its operands
  and accounting under the existing RTS lock.

No duplicate allocator lock, free-list authority, task-state authority, public
allocation API, or application-facing spawn/task dialect was added.

## Evidence

`scripts/verify-synchronization.sh` completed with
`FLYOLOGY:RTS:GATE:PASS` on 2026-08-15. Its constituent evidence includes:

- GNATprove FSF 16.1.0 at level 2: 537/537 generated checks proved, with no
  justified or unproved checks;
- tasking model: 313 edges, hash `6790843470299599875`;
- synchronization model: 224,969 edges, hash `12736863837444350006`;
- exact Ada allocator host gate and abort/exception black-box gates;
- both-target compiler-interface probes and interrupt-layout checks;
- exception-probe boots on x86-64 and AArch64 at SMP1 and SMP4;
- same-host independent-output-root tasking artifacts:
  x86-64 ELF `662d8df8f36b6155f995aca3e10cb2f0de8676f5a30ac031a8a9849f079b671e`,
  FAT `bed47f80702206ff921afd71e86ef10d5e83e51c1b39c9a348bd1b944cf7190a`,
  AArch64 ELF `e4e8fec4071cb56152b58e7b4525095f52627444fb8440d6326b67d68ef6e449`,
  FAT `78edf6efe419ff26043f85b56fefbe098801f336c7e1d568de463d38b5ed82a0`;
- inspected/unwind-checked tasking images and QEMU/UEFI product boots for both
  architectures at SMP1 and SMP4; and
- ten complete SMP4 synchronization stress runs per architecture.

The proof establishes runtime safety and the public geometry, accounting, and
rejected-state frame contracts of the exact allocator transition engine. The
smaller bounded model proves first-fit minimality and exact range updates; the
host gate exercises those behaviors on the production 4,096-unit state. Proof
does not cover the synchronized raw-address facade, architecture lock,
exception C, assembly, firmware, QEMU, or hardware. The concurrency and address
boundaries are exercised by the host and target gates above. Reproducibility
remains a same-host, two-output-root result rather than independently
provisioned builds.

## Clean-room and licensing boundary

The four allocator symbol profiles come from the recorded owned compiler
expansions and black-box probes. The replacement is original dual-licensed
Ada/SPARK; it does not use or adapt GNAT runtime source. Removing the allocator
C source does not change the documented external `libgcc` unwinder input or its
GCC Runtime Library Exception. The remaining C exception boundary is retained
because replacing a target DWARF personality/unwinder ABI with Ada would add
risk without removing the unavoidable foreign ABI.
