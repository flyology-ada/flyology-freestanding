# Minimal bootable application

This is a complete Alire application crate. Its ordinary Ada application
procedure invokes a small worker package containing eight tasks: two pinned to
each of four Ada CPUs. Every worker checks the standard `Get_CPU` observation
and rendezvouses with a printer task, which emits one complete line per accepted
call. `flyology_barebones` contributes the runtime, platform code, linker
scripts, boot-media builder, and the post-build image action.

```sh
alr build
```

The command produces:

- `build/x86_64/flyology-x86_64.fat`
- `build/aarch64/flyology-aarch64.fat`

Each image boots through Limine, prints exactly one line for every `(core,
worker)` pair, waits for all tasks to terminate, prints `OK`, finalizes the
application, and enters the platform idle/halt path.

Each architecture directory also contains `flyology.elf`, `uefi-code.fd`, and
`uefi-vars-template.fd`. The `.fd` files are the validated TianoCore/EDK II
firmware bundle used by the runner; they are adjacent machine firmware, not
files embedded in the guest FAT disk.

Run either image directly from the crate:

```sh
./run.sh x86_64
./run.sh aarch64
```

This example sets `FLYOLOGY_CPUS=4`, so both commands start four virtual CPUs.
The default interactive run stays attached after the application enters idle;
press Ctrl-C to stop QEMU. The wrapper resolves the dependency-provided runner
through `FLYOLOGY_RUN_TOOL`; neither the manifest nor the script contains an
absolute checkout or tool path.
