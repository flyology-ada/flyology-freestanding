# External input lock

All network-fetched binary inputs and hardware-emulation inputs are fail-closed pins. A version label without the listed digest is insufficient. Host image/test utilities used by the authoritative macOS gate are also version-and-digest checked below.

## Ada toolchain

The authoritative host path is Alire 2.1.1 with per-target local selections in `toolchains/`.

| Artifact | Version/origin | Digest |
| --- | --- | --- |
| x86-64 ELF GNAT | `gnat_x86_64_elf=15.3.1`, GNAT-FSF `15.3.0-1`, Darwin/AArch64 archive | SHA-256 `07e52e6ebdaaca0093b06cb5bd9c55a24ac464001282161f3d8113f8a0dab411` |
| AArch64 ELF GNAT | `gnat_aarch64_elf=15.3.1`, GNAT-FSF `15.3.0-1`, Darwin/AArch64 archive | SHA-256 `113b747396eb88ae46bdc29bf990a037edd4960f931ebc2513295e4573ae8ca0` |
| GPRbuild | `gprbuild=26.0.1`, Darwin/AArch64 archive | SHA-256 `6bf7d80c8a9702d851c5b992d7c72a07a9dbf13e8de9947b80927ea2667b6be8` |
| Native GNAT/GCC test compiler | `gnat_native=15.3.1`, GNAT-FSF `15.3.0-1`, Darwin/AArch64 executable | SHA-256 `fa728e60b2dc7e3dff407ab847725d8145f3301615bad70c39ef422c8e8b741d` |
| Native GNAT black-box build drivers | `GNATMAKE`, `GNATBIND`, and `GNATLINK` 15.3.0 from the same native bundle | SHA-256 `11a4aadc683258c5683cbb82b630e3cecc71ab6e628e825a1d27edc82faa4df3` (`gnatmake`), `ba3cc6aa2820b422b5686bb92d3c0391331f23c5d43a9e324b784b052c95a1bd` (`gnatbind`), `64b321899a9e2ba77210a25b2de503cf7858e503a50d029ea55f9772cf0292f3` (`gnatlink`) |
| LLVM object inspection tools | Homebrew LLVM `22.1.8`, Darwin/AArch64 `llvm-nm` and `llvm-objdump` | SHA-256 `98877e5da3a0591c4abeaf1819ca81976e886ec17550b10f81b0f5569890d5b5` (`llvm-nm`), `8d34812bfab8a85918ad8502890ef1c4dca02273687e0b5e4a18cd6864ce5e78` (`llvm-objdump`) |
| GNATprove executable | FSF `16.1.0`, installed native Darwin/AArch64 bundle | SHA-256 `1feba230ab840e8adff492d25c5beb231c9a89565fa11fed48c778e625cab900` |
| GCC sources (toolchain provenance only) | `gcc-15.3.0.tar.xz` | SHA-512 `0de9e296153b52c021b1c7e63c9c62151d7a0ac03f23ce6e9f772c1b0eb783f6acdd81cc4567bfe4128a6f64968c2cfc8eff40b36229cba7425349f7d637c654` |

Native GNAT 16.1.0 is intentionally not used for target compilation. The
pinned native GNAT/GCC 15.3 compiler is used only for host ABI/concurrency
tests; the current Alire cross releases are GCC/GNAT 15.3.0 and have no default
target runtime.

M4 exception images use only the generic `libgcc` unwinder contained in those
pinned compiler archives. The installed `libgcc.a` hashes are SHA-256
`b6d172e843239c3fa3906c0d972936a48ebf3d4249a0d0e723f83ecb18ff2304`
for x86-64 and
`0effb03f768225ce901b94e6ab108a3709b83bd2c879a629136b89b9bb0cd992`
for AArch64. They are external GCC Runtime Library material under the upstream
license and GCC Runtime Library Exception; no archive or GCC source is tracked.

GNATprove 16.1.0 is a native host proof tool, not a target runtime input. The proof gate checks both its first version line and the locally tested executable digest before analysis.

## TLA+ model checker

The bounded concurrency-design models use the external TLA+ 1.8.0 command-line
tools pre-release and OpenJDK 21.0.11. Neither artifact is tracked or linked
into the runtime. The official pre-release publishes SHA-1
`5288dcb2c48ece915768f61eaa1f117fd71044c6` for `tla2tools.jar`; the local gate
additionally pins its SHA-256.

| Artifact | Version/origin | SHA-256 |
| --- | --- | --- |
| `tla2tools.jar` | [TLA+ 1.8.0 official GitHub pre-release](https://github.com/tlaplus/tlaplus/releases/tag/v1.8.0) | `ab323b79802aedc3203b3f9af37c6aca3ed43f4e0225b36f2aa77b26de46c05f` |
| Java executable | Homebrew OpenJDK 21.0.11, Darwin/AArch64 | `04005388bac0c272ea914210ca519ce94b2f873ea3962b9874a6859f74d7f279` |

TLA+ tools are external MIT-licensed development inputs. The gate checks both
digests and the Java version before TLC runs. The models are design-level safety
evidence, not target-runtime dependencies or source-refinement proofs.

The GCC archive identifies the compiler source release and satisfies toolchain provenance. ADR-0004 forbids using its GNAT runtime sources as Flyology implementation inputs.

## Limine and protocol

Limine is pinned to immutable release `v12.5.2`, signed tag commit `fdc6d566072cc78a543cef44ef370729fe91fe2e`.

| Artifact | SHA-256 |
| --- | --- |
| `limine-12.5.2.tar.xz` | `37e55eb0e5f026333d303d4cb1e8c647db4b5613bd536c6602ae3fe43806eae2` |
| `limine-binary.tar.xz` | `5e2d6eb86623fcdcd2a873c9eca7dcafccb34182c17779535fe824fd57b688c5` |
| extracted `BOOTX64.EFI` | `d257add3b8ca480470c50ba5e55899702f19b10d9b29dc8d4a5db97fc4fb8b19` |
| extracted `BOOTAA64.EFI` | `b3510d5a3eae21517f73be939358f720266fe47f95abd249b78664171bd65c0e` |
| bundled `limine.h` | `4de542d1c232b230ca4af04c5b89a78f51c9bdacb928a94ac44fc88377208a63` |
| bundled `PROTOCOL.md` | `16da843c0d05f30309d34398a406107c84949abc8e87c6957cb0526b8316b6f8` |

The release bundles protocol commit `630686a3dd3ce40f9e510a7dd9fea6b4c60d952e`. Flyology requests base revision 6 and fails closed if unsupported. Base revision 6 disables AArch64 FP/SIMD/SVE at entry, so startup enables and normalizes the required state before Ada code can use it. x86 requests x2APIC and validates the response feature bit.

## QEMU machine contract

The first release pins QEMU 10.2.0 because that exact version is installed and executable on the development host. Floating `q35` and `virt` aliases are forbidden.

| Artifact | SHA-256 |
| --- | --- |
| official `qemu-10.2.0.tar.xz` | `9e30ad1b8b9f7b4463001582d1ab297f39cfccea5d08540c0ca6d6672785883a` |
| locally tested `qemu-system-x86_64` | `f716fea89cb460a085a2553c83f9a22501f2077a41af25c382b805a4cc2844f3` |
| locally tested `qemu-system-aarch64` | `33f0343582de8f0cf984857fe7e7f374f46a6dad4b7749d86450ede79ed029f3` |

Fixed launch geometry:

```text
x86-64:  -machine pc-q35-10.2 -accel tcg,thread=multi -cpu max,tsc-frequency=1000000000
AArch64: -machine virt-10.2,gic-version=3,virtualization=off,secure=off,dtb-randomness=off -accel tcg,thread=multi -cpu max
both:    -smp cpus=N,sockets=1,cores=N,threads=1   where N is 1 or 4
```

`virtualization=off` makes the QEMU AArch64 contract EL1, but startup still reads and validates `CurrentEL`. TCG is the reproducibility baseline on the Apple Silicon host; acceleration-specific coverage is not claimed.

The explicit x86 TSC frequency is part of the M4 clock contract. Flyology
calibrates each local x2APIC timer against it and makes no `invtsc` or physical
hardware claim. AArch64 uses the architected virtual counter frequency
reported by `CNTFRQ_EL0` on the pinned `virt-10.2` machine.

## UEFI firmware

M1 uses the firmware shipped with the pinned local QEMU 10.2.0 package and validates each file before launch:

| Image | SHA-256 |
| --- | --- |
| `edk2-x86_64-code.fd` | `33090cc07675baa5190d9f1e84bf5176b33bcbfa9bacac522961150cdb6dbb2a` |
| `edk2-i386-vars.fd` | `5d2ac383371b408398accee7ec27c8c09ea5b74a0de0ceea6513388b15be5d1e` |
| `edk2-aarch64-code.fd` | `47765fe344818cbc464b1c14ae658fb4b854f5c2ceffa982411731eb4865594d` |
| `edk2-arm-vars.fd` | `b3b855c5a80310168051164986855692d1bdb06e67619856177965cd87c6774f` |

Code images are read-only. Every test copies a pristine variables template because UEFI mutates it. These hashes pin tested binary inputs; they do not claim reproducible EDK II source builds.

## Host image and timeout utilities

The tested macOS gate uses GNU mtools 4.0.49. Homebrew installs `mformat`, `mmd`, `mcopy`, and `mdir` as links to one binary with SHA-256 `e8310ca53ac5f471b7cd8b0b4dacd2ef11a57e399e35d034d1b6899e49dd48a6`. The runner uses GNU coreutils `timeout` 9.11 at `/opt/homebrew/bin/gtimeout`, SHA-256 `96d98cb3adafdd41570802625f7511d7d340cbcd4cb7a7278d5706c282a59c33`. Scripts fail closed on version or digest drift; alternate builder environments must supply and document their own pinned utility contract.
