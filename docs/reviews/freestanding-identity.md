# Freestanding identity and namespace review

## Status

Complete for the product-identity migration. The reviewed implementation is
commit `1a344de3be02090348f76a47e2b66f4f2f1a2196`, Git tree
`180d40ea3614dca9ec61c7e93f04b2645f4a9d24`. This review is a documentation-only
follow-up and does not broaden any runtime capability or hardware claim.

The durable product and intended repository name is **Flyology Freestanding**.
Its Alire crate is `flyology_freestanding`, its Ada root is
`Flyology_Freestanding`, its owned ABI prefix is
`flyology_freestanding_*`, and its build-variable prefix is
`FLYOLOGY_FREESTANDING_*`. Consumer tools and artifacts use the
`flyology-freestanding-*` spelling.

## Reviewed migration

The audit covered all tracked paths and content, the Alire crate and independent
example, Ada units, GPR and proof projects, generated binder inputs, assembly/C
imports and exports, build/run scripts, clean-room inventories, documentation,
ELF symbol tables, FAT image names, and the TianoCore-assisted QEMU workflow.

This is a hard migration. There is no old crate alias, forwarding Ada root,
duplicate environment variable, linker-symbol shim, or compatibility tool.
Repository hygiene rejects reintroduction of any of those identities, and final
ELF inspection rejects an owned `flyology_*` symbol that is not under the
`flyology_freestanding_*` prefix.

The brand-level `FLYOLOGY:` structured diagnostic prefix is intentionally
unchanged. It is a serial protocol shared by Flyology projects, not an Ada,
Alire, linker, or repository namespace. The FAT volume label is likewise a
human-facing brand label and does not participate in compilation or linking.

## Clean-room boundary

The rename changes original Flyology-owned implementation and product surfaces;
it does not rename compiler-mandated GNAT interfaces. Predefined `Ada.*` and
`System.*` units, `__gnat_*` hooks, binder globals, firmware entry symbols, and
the compiler-facing `Ada.Task_Identification.Flyology` bridge retain the exact
spellings recorded by owned expansion, binder, symbol, representation, and
black-box probes. The last name is a private child of a language-defined package
and is not the product's Ada root.

All clean-room inventories were updated to the renamed implementation paths.
The authoritative tasking, synchronization, preemption-policy, and
dispatching-domain probes passed for both pinned target compilers; native
`Free_Task` lowering also passed. No GNAT runtime source was introduced or used
as rename evidence. This remains an engineering provenance statement rather
than legal advice or an intellectual-property warranty.

## Exact-tree evidence

`scripts/verify-domains.sh` completed on the reviewed commit with
`FLYOLOGY:DOMAINS:GATE:PASS`.

- Repository, clean-room, and product-project hygiene passed.
- GNATprove FSF 16.1.0 proved 543/543 generated checks at level 2, with no
  unproved or justified checks. The proof covers deterministic SPARK kernels;
  it does not cover concurrent kernel orchestration, GNARL facades, C exception
  unwinding, assembly, MMIO, or QEMU hardware.
- The tasking, RTS/synchronization, preemption-policy, and domain host models
  retained their pinned edge counts and hashes.
- TLC explored both scheduler policies, exact wait arbitration, and domain
  isolation. The domain model generated 17,035,809 states with 683,040 distinct
  states; the aggregate ended in `FLYOLOGY:FORMAL_MODELS:PASS`.
- Interrupt layout, final-ELF identity, and unwind gates passed on x86-64 and
  AArch64.
- Two independent output roots produced identical renamed ELF/FAT pairs.
- QEMU 10.2.0 TCG passed x86-64 `q35` and AArch64 `virt` at SMP1 and SMP4,
  followed by five SMP4 domain/preemption stress runs per architecture.

| Architecture | Domains ELF SHA-256 | Domains FAT SHA-256 |
| --- | --- | --- |
| x86-64 | `070620c9ee4259f95b3a960b116b6691ed28d61eb90235ccba0fff6f4309193b` | `f0ffdf79da086eb10db840ec19bd7203e3a8e63fc55f450cdf84d8921f914b75` |
| AArch64 | `92b3e0bf038f6db3b2739347cff6e13298ff275cdc81741ae8a6fbdea232347c` | `dc386141de18341797744667a67544ca9c6d09fb1f3196fac7fef106a8c5d140` |

`scripts/verify-minimal-example.sh` also completed on the exact commit with
`FLYOLOGY:EXAMPLE:MINIMAL:GATE:PASS`. Alire 2.1.1 resolved the local
`flyology_freestanding` dependency, built both architectures twice, obtained
identical output pairs, validated the pinned TianoCore code/variables images,
and booted the ordinary-Ada worker/rendezvous example on both target machines.
Tracked Alire metadata contains no absolute checkout path.

| Architecture | Example ELF SHA-256 | Example FAT SHA-256 |
| --- | --- | --- |
| x86-64 | `48e7a2439f42f853184374c13cabebfd4f54584a99a1d1ad75bbe4541ca25a98` | `51b2304de882a9307e4c2b6cc34c5b92c563b94a2fc693ec85db7c7204d8239d` |
| AArch64 | `343d034f80b17a7f89dbbcca66968bafc893f0cdcbbe8fe0ff6e3759e37f51e5` | `13308a3bdc6c1dc0aa4f1695812f08ae0279a3d721ee7f88ac31b0e6e239a361` |

The host primitive archive is
`libflyology_freestanding_primitives.a`, SHA-256
`6fd5201acd29dc5b80d349f2952159adaf8f9a585cf72d26659805af02baffb3`.
Pinned target compilers remain GNAT-FSF 15.3.0 as packaged by the Alire 15.3.1
cross releases. External input versions and digests remain authoritative in
`docs/external-inputs.md`.

## Findings and dispositions

### Blocker — the generic Ada root collides with another Flyology crate

Disposition: fixed. All original product packages now descend from
`Flyology_Freestanding`; compiler-facing predefined units remain separate. The
independent Alire example compiled and booted the renamed root on both targets.

### High — build and private ABI names preserve the same collision

Disposition: fixed across Alire exports, GPR externals, shell configuration,
assembly/C symbols, generated launcher/binder names, libraries, tools, and
artifacts. Source and ELF hygiene make the new prefix fail-closed.

### High — a compatibility layer would keep two identities alive

Disposition: subtracted. No aliases or forwarding units were added. Consumers
must migrate once while the crate remains `0.1.0-dev`.

### Review blocker — the residual-name gate rejected the migration ADR

Disposition: fixed and amended into the implementation commit. The checker now
permits the retired human-readable name only in ADR-0013, where documenting the
decision requires it, while continuing to reject it in every other tracked
path.

### Review blocker — the residual-symbol gate rejected its own ELF inspector

Disposition: fixed and amended into the implementation commit. The broad old
prefix is allowed only in the two enforcement scripts that must search for it;
all product sources, tests, configuration, other tooling, and final ELF symbols
remain covered.

## Residual limits

- Renaming or creating the remote GitHub repository is an external hosting
  operation and was not performed by this source-tree change. The intended
  remote name is `flyology-freestanding`.
- The existing local checkout directory retains its historical filesystem name.
  It is not tracked metadata or a consumer-visible path; a later move or fresh
  clone can align it with the repository name without changing source.
- Generated ignored build directories may contain stale files from earlier
  local builds. Authoritative clean/reproducible output roots and all published
  artifact names use the new identity; generated outputs remain outside version
  control.
- Same-host independent-output-root reproducibility is demonstrated, not
  independently provisioned builders or hosted CI.
- Execution evidence remains the pinned QEMU virtual-machine contract, not
  physical hardware or arbitrary UEFI firmware.

Within those limits, the source, package, ABI, tooling, artifact, consumer, and
clean-room identities are coherent and no longer collide with a separate
Flyology application/core library.
