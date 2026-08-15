# Build the runtime

Flyology has three complementary build products: a reusable host-side archive
of deterministic primitives, repository conformance images, and freestanding
images supplied by independent application crates. They share sources and
contracts but have different toolchain and linking needs.

## Deterministic primitive library

The root Alire crate builds `libflyology_primitives.a` from the Ada/SPARK
packages in `src/primitives`. The concurrent `Flyology.Kernel` authority lives
separately under `src/kernel` and is not part of this host archive. Select the
pinned native tools recorded in `docs/external-inputs.md`,
then build:

```sh
alr -n toolchain --select --local gnat_native=15.3.1 gprbuild=26.0.1
alr build --release
```

The archive is written to `build/alire/lib/`. It contains deterministic
validation, task-state, wait, timer, priority, domain, allocator, and scheduling
algorithms. It is useful independently for proof, host exploration, and future
kernel composition. It does not contain the concurrent dispatcher, GNARL facade,
foreign exception/allocator ABI, boot code, or target assembly, and therefore is
not itself a freestanding Ada runtime image.

Alire workspace state remains generated and ignored. The source manifest is
`alire.toml`; exact compiler and builder inputs remain governed by the external
input lock rather than an unreviewed per-machine workspace setting.

## Freestanding images

The image combines the deterministic primitives with `src/kernel`, `src/rts`,
the clean-room compiler facades in `src/gnarl`, platform code, and one target
conformance scenario. Build it through the capability entry point:

```sh
scripts/build-product.sh ARCH PROFILE
```

`ARCH` is `x86_64` or `aarch64`. The profiles are defined in
`config/profiles.toml`:

| Profile | Capability |
| --- | --- |
| `tasking` | cooperative ordinary-Ada tasking and synchronization runtime |
| `preemptive-fifo` | timer/IPI preemption with FIFO-within-priorities |
| `preemptive-round-robin` | timer/IPI preemption with round-robin-within-priorities |
| `domains` | scheduling domains with the currently gated domain configuration |

The stable image name is `build/product/PROFILE/ARCH/flyology.elf`; the FAT image
is adjacent. The builder uses the pinned per-target Alire workspaces, explicit
GNAT binder step, target linker script, external `libgcc` unwinder, and pinned
Limine/firmware image construction.

Ada compilation is owned by `gpr/flyology_image.gpr`. Its source directories
are the responsibility-owned runtime roots plus exactly one selected scheduler,
domain, configuration view, and application directory. A generated
`Flyology_Launcher` is the binder main: it explicitly validates RTS elaboration
and invokes the selected ordinary-Ada application procedure. Runtime authority,
standard-library finalization, and the two validation bodies are explicit
project roots because architecture entry code and foreign binder boundaries
reference them directly. GPRbuild discovers the remaining Ada units from
dependencies; the shell builder does not carry a second Ada source or object
list.

The cross compilers intentionally ship without an installed default Ada
runtime. `gpr/flyology_cross.cgpr` therefore describes the unit-based compiler
protocol without naming a runtime directory. `scripts/toolchain.sh` supplies
the concrete compiler, archiver, and indexer paths from the pinned Alire
workspace as external project values. The configuration file is relocatable
and contains no developer-machine toolchain path.

After GPR compilation, `scripts/build-image.sh` generates a sorted response file
from the project objects. It still performs the explicit GNAT binder step,
compiles the generated binder body, compiles the narrow assembly/C platform and
ABI objects, invokes the architecture linker script with pinned `libgcc`, and
constructs the Limine FAT image. Those are freestanding ABI and image-composition
responsibilities; they are not an alternate Ada build graph.

The current conformance image main and ordinary-Ada behavioral scenarios live
under `tests/target/scenarios/`. They are linked test clients of the runtime, not
runtime library sources. Structured serial markers therefore describe a scenario
assertion and do not enlarge the product API.

## Independent application crates

The root Alire manifest contributes relocatable `FLYOLOGY_BUILD_TOOL` and
`FLYOLOGY_RUN_TOOL` values to a dependent crate's build environment. The
consumer identifies one source directory and parameterless Ada procedure; it
does not name target sources, predefined units, linker scripts, firmware, or
QEMU options. `alr build` may use the dependency-provided post-build action to
produce both architecture bundles. The dependency does not mutate `PATH`, so
Alire's generated build inputs do not capture developer-machine path entries.

Consumer artifacts use `build/ARCH/` rather than the repository's deeper
profile matrix. A selected profile is one build configuration and intentionally
does not appear in the default consumer path. The repository gates retain
`build/product/PROFILE/ARCH/` because they compare several profiles side by
side.

Each consumer architecture directory contains the ELF, Limine FAT disk, and
copies of the pinned TianoCore code/variables firmware. The firmware is kept
adjacent because it belongs to the emulated machine, not to the guest disk.
`scripts/flyology-run` uses those copies and creates a private mutable variables
file for each run. The complete contract and example are in
[`docs/application-crates.md`](application-crates.md).

Each capability profile records the same target project and cross-toolchain
configuration in `config/profiles.toml`, then configures one
`scripts/build-image.sh` composition builder. Capability verification scripts
consume that same path; there is no parallel product graph.
`scripts/verify-product-build.sh` rebuilds every profile in two independent
output roots for both targets and requires identical ELF and FAT SHA-256 values.

The isolated exception-boundary image is a verification client rather than a
product profile. Its Ada closure is nevertheless project-owned by
`gpr/flyology_exception_probe.gpr`; `scripts/build-exception-probe.sh` performs
only the corresponding freestanding binder/link/media composition. The
synchronization gate runs that image on both targets at SMP1 and SMP4.
