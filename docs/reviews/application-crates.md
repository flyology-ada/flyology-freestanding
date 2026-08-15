# Application-crate workflow review

## Status

Complete for the application-crate workflow capability. The reviewed
implementation is commit `8f7947213342277cdc99e2be13752b3ef4036711`, Git tree
`b7f477e07b5c0104808860b452d57836afbbbaa3`. The closing review and roadmap
change documentation only.

An independent Alire crate can now depend on `flyology_freestanding`, name one
ordinary parameterless Ada procedure, and receive bootable x86-64 and AArch64
images from `alr build`. The dependency owns the target project, clean-room RTS,
platform sources, linker scripts, Limine media construction, pinned TianoCore
firmware selection, and QEMU machine contract. The consumer does not enumerate
target-specific GPR sources or linker inputs.

## Reviewed public workflow

- The dependency exports `flyology-freestanding-build` and `flyology-freestanding-run` through its Alire
  environment.
- The consumer supplies `FLYOLOGY_FREESTANDING_APPLICATION_UNIT`; the tools infer the crate
  root and conventional `src/` directory from their invocation context.
  `FLYOLOGY_FREESTANDING_APPLICATION_ROOT` and `FLYOLOGY_FREESTANDING_APPLICATION_DIR` remain optional
  overrides for nonstandard layouts. The generated `Flyology_Freestanding_Launcher` is the
  binder main and invokes that procedure after the RTS elaboration closure.
- `Flyology_Freestanding.Console.Put_Line` is the only new application-facing runtime API.
  It delegates to one narrow platform serial boundary and exposes no task,
  scheduler, context, or wait authority.
- The default post-build action produces both supported architectures. A caller
  may select one architecture; scheduling policy is declared in consumer Ada,
  not selected through this action.
- `flyology-freestanding-run` accepts the architecture and CPU count, uses the pinned fixed
  QEMU machine, copies the mutable UEFI variables template per run, and supports
  a bounded timeout for automation. Its default remains headless; an explicit
  `--gui` option enables QEMU's host display without changing the guest image.

Consumer outputs are deliberately shallow:

```text
build/
  x86_64/
    flyology-freestanding.elf
    flyology-freestanding-x86_64.fat
    uefi-code.fd
    uefi-vars-template.fd
  aarch64/
    flyology-freestanding.elf
    flyology-freestanding-aarch64.fat
    uefi-code.fd
    uefi-vars-template.fd
```

The prior `build/flyology/tasking/...`-style path exposed a repository profile
matrix as if it were an application concept. It is removed from the consumer
surface. Repository conformance gates retain `build/product/PROFILE/ARCH/`
because those gates compare multiple profiles simultaneously; that internal
matrix is not the output contract of an application crate.

The FAT disk contains the architecture-specific Limine UEFI loader,
configuration, and kernel ELF. TianoCore/EDK II code and variables images remain
adjacent: they initialize the emulated machine and are not guest-disk files.
Generated firmware copies and all other build outputs remain ignored.

## Clean-room review

The application procedure, generated launcher, console API, image layout, and
QEMU runner are original product/build surfaces. They are not compiler-facing
GNARL/GNULL interfaces and do not change
`docs/clean-room/interfaces.toml` or any clean-room implementation inventory.

The target compiler still sees only the recorded predefined-unit and tasking
interfaces discovered from the Ada Reference Manual, public compiler material,
Flyology Freestanding-owned compiler expansion/binder output, diagnostics, representation
records, disassembly, and black-box tests. No GNAT runtime source was inspected,
copied, or linked by this workflow. This is an engineering provenance statement,
not legal advice or an intellectual-property warranty.

TianoCore/EDK II, Limine, the target compilers, `libgcc`, mtools, QEMU, and the
timeout utility remain external inputs under `docs/external-inputs.md`. The
bundle step copies validated firmware artifacts into ignored output directories;
it does not vendor them into the source crate or relicense them as Flyology Freestanding code.

## Exact-tree evidence

`scripts/verify-minimal-example.sh` completed with
`FLYOLOGY:EXAMPLE:MINIMAL:GATE:PASS` on the reviewed implementation. It ran the
independent crate through Alire 2.1.1, built both architectures in two output
roots, required byte-identical ELF/FAT/firmware hashes, validated both pinned
TianoCore code and variable images, and booted both FAT disks through the shared
runner with a 12-second timeout.

Both serial logs contained exactly one `OK`, one
`FLYOLOGY:ADA:MAIN:PASS`, and one
`FLYOLOGY:TASKING:BOOT_SUBSTRATE:PASS`, in causal order, with no Flyology Freestanding failure
or panic marker. Returning from the consumer procedure therefore exercised
binder finalization, environment-task termination, and the idle/halt path rather
than relying on a test-only exit primitive.

| Architecture | ELF SHA-256 | FAT SHA-256 | TianoCore code SHA-256 | TianoCore variables SHA-256 |
| --- | --- | --- | --- | --- |
| x86-64 | `198f29aa0feec0a0739d7d741a415c0964c4e4a1fcb6a671b4ed5ddb327ff60f` | `248b8e0659021d24b50724ab268d2a1b9d34a6bd0fab713d8d01fe7a3fd86a80` | `33090cc07675baa5190d9f1e84bf5176b33bcbfa9bacac522961150cdb6dbb2a` | `5d2ac383371b408398accee7ec27c8c09ea5b74a0de0ceea6513388b15be5d1e` |
| AArch64 | `bcac7798d9d2fa241e979160422769ae7652cc55ab999c02755a086e865e65f0` | `42ca68894fa5aa77a36c347d0ce669747db7079719a1f60982011e41dc15aab1` | `47765fe344818cbc464b1c14ae658fb4b854f5c2ceffa982411731eb4865594d` | `b3b855c5a80310168051164986855692d1bdb06e67619856177965cd87c6774f` |

`scripts/check.sh` also completed with `FLYOLOGY:CHECK:PASS`, including the
clean-room and product-project hygiene checks. `alr -n build --release` built
the reusable host archive with SHA-256
`36ba618da57f0b22b9b659f7bce26a8824603a01d7c3e2d16e32b230e4801914`.
The pinned target toolchains are GNAT-FSF 15.3.0 as packaged by Alire 15.3.1;
execution is QEMU 10.2.0 TCG on the fixed `pc-q35-10.2` and `virt-10.2` machine
contracts.

## Findings and dispositions

### High — public image paths encode an internal conformance profile

Disposition: fixed. Consumer artifacts now use `build/ARCH/`. Profile nesting
is confined to repository gates that actually compare several profiles.

### High — application crates must reproduce the target GPR graph

Disposition: fixed. The dependency owns one configurable target project and
generates its binder launcher. The consumer GPR file is a small host-phase Alire
placeholder and contains no target-specific source, linker, firmware, or QEMU
configuration.

### High — the UEFI disk is not directly runnable without firmware knowledge

Disposition: fixed. Each architecture bundle includes digest-validated
TianoCore code and variable images, and the shared runner owns their correct
read-only/mutable use. The low-level UEFI runner is shared with repository
conformance gates rather than duplicated.

### Medium — returning from the application has ambiguous halt semantics

Disposition: documented and tested. Return performs normal finalization and
task termination; with no Ready task the dispatcher executes `hlt`/`wfi`. The
interactive runner remains attached by design, while verification uses a
timeout and asserts the finalization markers.

## Residual limits

- The example uses a local path pin because it lives in this repository. A
  published consumer uses the normal Alire index or its own explicit pin.
- The dependency does not download toolchains, Limine, QEMU, or firmware at
  application-build time. The exact external-input contract must already be
  installed or fetched by the repository bootstrap process.
- Same-host, two-output-root determinism is demonstrated. Independently
  provisioned builders and hosted CI are not claimed.
- Runtime execution evidence remains the pinned QEMU TCG machines. Physical
  UEFI hardware and other firmware releases are not claimed.
- The host-only consumer GPR placeholder is an Alire packaging constraint, not
  a second target build graph. A future Alire-native target action may remove it
  without changing the runtime or image contract.

Within those limits, the application-crate workflow is complete: a small Ada
crate can build, inspect, and run deployable UEFI images for both supported
architectures without reproducing Flyology Freestanding's target project.

## Observation-policy amendment — 2026-08-15

Implementation commit `f8844cf39c121956aa95005d56f94251ff43d5fc`, Git tree
`f3323300d1b9be0028edc711b96c97184b99a4ee`, separates repository test
observations from consumer output. `flyology-freestanding-build` now selects
`FLYOLOGY_FREESTANDING_TEST_OBSERVATIONS=0` unless the application explicitly opts in;
repository conformance composition retains the enabled default. Fatal
`FLYOLOGY:FAIL`/`PANIC` diagnostics and `Flyology_Freestanding.Console` output are outside
this switch.

The exact implementation tree passed `scripts/verify-minimal-example.sh` on
x86-64 SMP4 and AArch64 SMP4. Each quiet serial log contained the eight exact
worker records and `OK`, with zero Ada, core-online, tasking-boot, or RTS
finalization observation markers and no failure/panic marker. Independent
output-root images were byte-identical:

| Architecture | Quiet ELF SHA-256 | Quiet FAT SHA-256 |
| --- | --- | --- |
| x86-64 | `bbf29b98ede30ad9b45c79df111f37a8b4b2dbb35ba390464c4f41c323b1a6ae` | `4f2e8a079265a6b33221434712a75d9e99e1ad1bbd7590eba5c129d8b774cc5c` |
| AArch64 | `477f486b8fffc1586aba90b609a65f1da1da1508a2a3c80ad1e3bb9f927545b9` | `01f58447afd778e223dbb46149b36d2b65728f3148d6601d2705963f5a56a1e8` |

The complementary tasking conformance image was freshly rebuilt and passed
`scripts/run-image.sh ARCH 1 tasking` on both architectures. Each log retained
exactly one Ada-main and tasking-boot observation along with the complete
machine-checked tasking marker set. This demonstrates that suppression is an
application composition policy, not deletion or weakening of behavioral-gate
evidence. The switch and documentation are original Flyology Freestanding build/test
surfaces and do not change a compiler-facing clean-room interface.
