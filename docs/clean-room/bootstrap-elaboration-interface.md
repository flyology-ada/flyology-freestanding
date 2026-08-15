# bootstrap checkpoint compiler-interface evidence

This record covers only the sequential binder and fail-closed diagnostic surface used by bootstrap checkpoint. It is not a GNARL or exception-propagation claim. Both isolated probes used Flyology-owned Ada programs with the pinned GNAT 15.3.0 cross compilers and did not read GNAT runtime source.

## Binder elaboration

An owned empty main plus an owned package with a body was compiled using `-nostdinc`. `gnatbind -nostdinc -nostdlib -n -minimal` first diagnosed the missing runtime units and symbols. The minimal source surface that made the generated binder unit compile and link was:

- `System.Address`, a 64-bit modular type, and `System.Null_Address`;
- `System.Standard_Library.AdaFinal`;
- fourteen binder policy globals;
- `__gnat_finalize_library_objects`;
- `__gnat_runtime_initialize(Integer)` and `__gnat_runtime_finalize`.

The generated binder calls the owned package elaboration body from `adainit`. bootstrap checkpoint reproduces the probe directly: `scripts/build-bootstrap.sh ARCH` compiles the tracked sources, runs the binder command recorded in that script, and rejects any undefined final symbol. Startup performs `adainit`, the Ada main, then `adafinal`. The Ada main observes state written only by the package elaboration body before returning, so the emitted `FLYOLOGY:ADA:MAIN:PASS` marker proves the binder path ran.

## Last-chance ABI

The isolated discovery probe exercised explicit `Constraint_Error`, `Program_Error`, and `Storage_Error` raises plus an implicit range check. The permanent bootstrap checkpoint product surface is intentionally narrower: only the tracked `Program_Error` probe is built into the negative image, while the other names are reserved forwarding entries discovered by that isolated experiment and are not claimed as independently reproducible in-tree conformance tests.

- `__gnat_rcheck_CE_Explicit_Raise`;
- `__gnat_rcheck_PE_Explicit_Raise`;
- `__gnat_rcheck_SE_Explicit_Raise`;
- `__gnat_rcheck_CE_Range_Check`.

Disassembly showed the same two-argument C ABI as the publicly documented `__gnat_last_chance_handler`: a NUL-terminated source-location address followed by an integer line. Original non-returning forwarding entries linked every isolated probe with no undefined symbols.

The reproducible in-tree negative probe is `tests/legacy/checkpoints/bootstrap/flyology_last_chance_probe.adb`, which uses an ordinary Ada `raise Program_Error`. Run `FLYOLOGY_BOOT_VARIANT=last-chance scripts/build-bootstrap.sh ARCH`; the test gate machine-checks that this owned object has exactly one undefined compiler call, `__gnat_rcheck_PE_Explicit_Raise`, that the final ELF contains the probe and has no undefined symbols, and that QEMU emits exactly one architecture-specific `FLYOLOGY:LAST_CHANCE` marker without any Ada-main, bootstrap checkpoint-pass, generic failure, or panic marker.

bootstrap checkpoint compiles under the explicit `No_Exception_Propagation` restriction in `config/restrictions/bootstrap.adc`. Ordinary handlers require unwinding, personality, exception descriptors, and handler lifecycle symbols that bootstrap checkpoint does not implement. Consequently, the bootstrap checkpoint shims are terminal diagnostics, not Ada exception propagation. This temporary restriction and these narrowly observed shims cannot be used to claim full GNARL completion.

## Limine compatibility records

The request identifiers and record ordering in
`src/platform/*/limine_requests.S` are compatibility constants copied from
Limine's 0BSD protocol header at the exact revision pinned in
`docs/external-inputs.md`. The linker asserts the complete six-request region is
exactly 400 bytes, and `scripts/inspect-bootstrap.sh` independently checks every
record offset, final-ELF geometry, relocation state, required symbol, and empty
undefined-symbol set. Response fields are consumed according to the public
protocol record layout, with revision, count, pointer, paging-mode, x2APIC,
extent, memory-type, overlap, translated-range, and topology-identity validation
before AP release.
