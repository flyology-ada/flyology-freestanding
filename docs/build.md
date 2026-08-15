# Build the runtime

Flyology has two complementary build products during productization: a reusable
host-side archive of deterministic primitives, and freestanding target images.
They share sources and contracts but have different toolchain and linking needs.

## Deterministic primitive library

The root Alire crate builds `libflyology_primitives.a` from the Ada/SPARK
packages in `runtime/core`. The concurrent `Flyology.Kernel` authority lives
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

The current conformance image main and ordinary-Ada behavioral scenarios live
under `tests/target/scenarios/`. They are linked test clients of the runtime, not
runtime library sources. Structured serial markers therefore describe a scenario
assertion and do not enlarge the product API.

During this migration slice the profile entry point delegates compilation to
the reviewed milestone builders. `scripts/verify-product-build.sh` builds the
`domains` image through both paths for both targets and requires identical ELF
and FAT SHA-256 values. Later slices move compilation ownership into component
GPR projects; the differential gate remains until the historical builders are
quarantined and removed.
