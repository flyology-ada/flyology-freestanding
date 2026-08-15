# Building application crates

`flyology_barebones` is both a deterministic primitive library and a provider
of a freestanding image toolchain. An application crate supplies one ordinary
Ada library procedure. The dependency owns RTS elaboration, binding, platform
assembly, linking, Limine media construction, TianoCore firmware selection,
and QEMU machine arguments.

## Minimal crate contract

Add the dependency and identify the application procedure in `alire.toml`:

```toml
[[depends-on]]
flyology_barebones = "*"

[environment]
FLYOLOGY_APPLICATION_UNIT.set = "my_kernel"

[[actions]]
type = "post-build"
command = ["sh", "-c", "exec \"$FLYOLOGY_BUILD_TOOL\""]
```

The tools infer the application root from the directory in which Alire runs
and use its conventional `src/` directory. `FLYOLOGY_APPLICATION_ROOT` and
`FLYOLOGY_APPLICATION_DIR` are optional overrides for nonstandard layouts;
ordinary crates should not repeat those paths in their manifests.

During local development a normal Alire path pin can select a checkout. A
published crate does not retain that pin.

The consumer GPR project is only Alire's host-build placeholder. It does not
list runtime, platform, linker, or target sources. The complete example is
[`examples/minimal`](../examples/minimal/); copying its small `minimal.gpr`
requires no target-specific GPR configuration.

The application source is an ordinary parameterless procedure:

```ada
with Flyology.Console;

procedure My_Kernel is
begin
   Flyology.Console.Put_Line ("OK");
end My_Kernel;
```

The repository's complete minimal example goes one step further: it sets
`FLYOLOGY_CPUS=4`, starts two ordinary Ada workers on each core with the `CPU`
aspect, and routes every complete output line through a printer-task rendezvous.
Its enclosing Ada master waits for every worker and the printer before emitting
the final `OK`.

`alr build` builds both supported architectures by default. The output is
deliberately shallow:

```text
build/
  x86_64/
    flyology.elf
    flyology-x86_64.fat
    uefi-code.fd
    uefi-vars-template.fd
  aarch64/
    flyology.elf
    flyology-aarch64.fat
    uefi-code.fd
    uefi-vars-template.fd
```

The FAT disk contains the architecture-specific Limine UEFI loader,
`limine.conf`, and `kernel.elf`. TianoCore code and variable images are machine
firmware, so they remain adjacent to the disk rather than being embedded in it.
The runner copies the variables template before every launch because UEFI
variable storage is mutable.

Build one architecture or select another runtime profile explicitly:

```sh
alr exec -- sh -c 'exec "$FLYOLOGY_BUILD_TOOL" "$@"' flyology-build x86_64
alr exec -- sh -c 'exec "$FLYOLOGY_BUILD_TOOL" "$@"' flyology-build \
  --profile preemptive-fifo aarch64
```

The example includes a relocatable `run.sh` wrapper. Run a built image with the
pinned QEMU/EDK II contract:

```sh
./run.sh x86_64
./run.sh --cpus 4 aarch64
./run.sh --gui x86_64
```

Runs are headless by default for deterministic terminal use and automation.
`--gui` leaves QEMU's host display enabled while retaining serial output in the
terminal. It prepares the runner for a future guest framebuffer; it does not by
itself add or initialize a framebuffer device in the Ada application.

The dependency exports `FLYOLOGY_BUILD_TOOL` and `FLYOLOGY_RUN_TOOL` as paths
relative to its own Alire crate root. It does not prepend its scripts directory
to `PATH`. Consequently tracked Alire metadata and generated build-hash inputs
do not capture a developer checkout or the host's absolute `PATH` entries.

Returning from the application procedure performs binder finalization and
terminates the environment task. With no remaining Ready tasks, each core
enters the architecture idle instruction (`hlt` or `wfi`). The interactive
runner therefore remains attached until interrupted; `--timeout SECONDS` is
available for bounded automation in either display mode.

## Boundary and clean-room status

The generated `Flyology_Launcher` is original Flyology build orchestration. It
is the binder main so RTS elaboration does not depend on whether an application
happens to declare tasks. `Flyology.Console` is an original application API
over a narrow platform serial boundary. Neither surface is compiler-facing and
neither adds a GNARL/GNULL interface to the clean-room inventory.

Compiler-facing packages remain exactly those indexed by
[`docs/clean-room/interfaces.toml`](clean-room/interfaces.toml). Consumer source
is never evidence for their shape. The target compiler, binder, `libgcc`,
Limine, mtools, QEMU, EDK II, and timeout inputs retain the exact version and
digest contract in [`docs/external-inputs.md`](external-inputs.md).
