# Reproducible toolchain contract

bootstrap-minimum checkpoint uses two independent Alire workspaces so selecting one cross-compiler cannot silently replace the other. `scripts/toolchain.sh` is the authoritative entry point.

Pinned tools:

| Input | Pin | macOS/AArch64 origin SHA-256 |
| --- | --- | --- |
| Alire | 2.1.1 | Host prerequisite; installation provenance must be recorded by clean-room runs. |
| `gnat_x86_64_elf` | 15.3.1 (`gnat-15.3.0-1` archive) | `07e52e6ebdaaca0093b06cb5bd9c55a24ac464001282161f3d8113f8a0dab411` |
| `gnat_aarch64_elf` | 15.3.1 (`gnat-15.3.0-1` archive) | `113b747396eb88ae46bdc29bf990a037edd4960f931ebc2513295e4573ae8ca0` |
| `gprbuild` | 26.0.1 (`gprbuild-26.0.0-1` archive) | `6bf7d80c8a9702d851c5b992d7c72a07a9dbf13e8de9947b80927ea2667b6be8` |

Install without changing a global Alire toolchain selection:

```sh
scripts/toolchain.sh install x86_64
scripts/toolchain.sh install aarch64
```

Run a command inside one selected environment:

```sh
scripts/toolchain.sh exec x86_64 x86_64-elf-gnatls -v
scripts/toolchain.sh exec aarch64 aarch64-elf-gnatls -v
```

The compiler hashes above are the Alire origin hashes reported for Darwin/AArch64. Linux clean-room builder origins have distinct archives and must be recorded separately if that fallback is activated. An installed toolchain is necessary but not sufficient evidence for bootstrap-minimum checkpoint: the gate also records compiler/runtime identity, input hashes, both ELF inspections, and a second clean build with matching output hashes.

The current Alire index also offers native GNAT 16.1.0. That is not a substitute for the target compilers: as of this pin, both `gnat_x86_64_elf` and `gnat_aarch64_elf` top out at 15.3.1. Target code therefore uses GCC/GNAT 15.3.0 as packaged by the 15.3.1 Alire releases. The cross compilers intentionally provide no default Ada runtime; Flyology Freestanding supplies an original clean-room compiler-compatible runtime rather than linking a hosted runtime.
