# M0 package `System` probe

An isolated agent with no repository or GNAT-runtime-source context created this
owned probe:

```ada
procedure Noop
  with Export,
       Convention    => C,
       External_Name => "noop";

procedure Noop is
begin
   null;
end Noop;
```

With no `system.ads`, both compilers fail with `cannot locate file system.ads`.
With the original empty declaration below, both compile successfully under
`-gnat2022 -gnatg -nostdinc -I.`:

```ada
package System is
end System;
```

Validated compilers and output:

- `x86_64-elf-gcc (GNAT-FSF-builds) 15.3.0` produced an x86-64 ELF relocatable
  with global `noop` and `noop_E` symbols.
- `aarch64-elf-gcc (GNAT-FSF-builds) 15.3.0` produced an AArch64 ELF relocatable
  with the same global symbols.
- The `.ali` dependency list names the local `system.ads`, showing that the probe
  consumed it.

No private target parameters, address types, priorities, or floating-point
characteristics are required by this exact M0 program. They are therefore
omitted. Later clean-room records add only the surface demonstrated necessary by
an owned language-feature probe. No GNAT runtime source was used in this evidence
pass.
