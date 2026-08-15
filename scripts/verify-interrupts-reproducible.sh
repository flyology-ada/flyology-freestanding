#!/bin/sh
set -eu

for architecture in x86_64 aarch64; do
    scripts/build-interrupts.sh "$architecture" >/dev/null
    first_elf=$(shasum -a 256 "build/interrupts/$architecture/flyology-interrupts.elf")
    first_disk=$(shasum -a 256 "build/interrupts/$architecture/flyology-$architecture.fat")

    scripts/build-interrupts.sh "$architecture" >/dev/null
    second_elf=$(shasum -a 256 "build/interrupts/$architecture/flyology-interrupts.elf")
    second_disk=$(shasum -a 256 "build/interrupts/$architecture/flyology-$architecture.fat")

    test "$first_elf" = "$second_elf"
    test "$first_disk" = "$second_disk"
    printf '%s\n%s\n' "$second_elf" "$second_disk"
done

echo 'FLYOLOGY:INTERRUPTS:REPRODUCIBLE:PASS'
