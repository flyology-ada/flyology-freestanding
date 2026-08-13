#!/bin/sh
set -eu

for architecture in x86_64 aarch64; do
    scripts/build-m1.sh "$architecture" >/dev/null
    first_elf=$(shasum -a 256 "build/m1/$architecture/flyology-m1.elf")
    first_disk=$(shasum -a 256 "build/m1/$architecture/flyology-$architecture.fat")

    scripts/build-m1.sh "$architecture" >/dev/null
    second_elf=$(shasum -a 256 "build/m1/$architecture/flyology-m1.elf")
    second_disk=$(shasum -a 256 "build/m1/$architecture/flyology-$architecture.fat")

    test "$first_elf" = "$second_elf"
    test "$first_disk" = "$second_disk"
    printf '%s\n%s\n' "$second_elf" "$second_disk"
done

echo 'FLYOLOGY:M1:REPRODUCIBLE:PASS'
