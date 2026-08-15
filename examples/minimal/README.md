# Minimal bootable application

This is a complete Alire application crate. Its only application source is an
ordinary Ada main. `flyology_barebones` contributes the runtime, platform code,
linker scripts, boot-media builder, and the `flyology-build` post-build action.

```sh
alr build
```

The command produces:

- `build/x86_64/flyology-x86_64.fat`
- `build/aarch64/flyology-aarch64.fat`

Each image boots through Limine, prints `OK`, returns from the environment Ada
procedure, finalizes the application, and enters the platform idle/halt path.

Each architecture directory also contains `flyology.elf`, `uefi-code.fd`, and
`uefi-vars-template.fd`. The `.fd` files are the validated TianoCore/EDK II
firmware bundle used by the runner; they are adjacent machine firmware, not
files embedded in the guest FAT disk.

Run either image directly from the crate:

```sh
alr exec -- flyology-run x86_64
alr exec -- flyology-run aarch64
```

Pass `--cpus 4` to use four virtual CPUs. The default interactive run stays
attached after the application enters idle; press Ctrl-C to stop QEMU.
