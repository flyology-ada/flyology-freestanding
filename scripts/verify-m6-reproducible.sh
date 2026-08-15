#!/bin/sh
set -eu

first=build/reproducible/m6-first
second=build/reproducible/m6-second

for architecture in x86_64 aarch64; do
    FLYOLOGY_M6_OUTPUT_ROOT=$first scripts/build-m6.sh "$architecture" >/dev/null
    FLYOLOGY_M6_OUTPUT_ROOT=$second scripts/build-m6.sh "$architecture" >/dev/null

    first_elf=$(shasum -a 256 "$first/$architecture/flyology.elf")
    second_elf=$(shasum -a 256 "$second/$architecture/flyology.elf")
    first_disk=$(shasum -a 256 "$first/$architecture/flyology-$architecture.fat")
    second_disk=$(shasum -a 256 "$second/$architecture/flyology-$architecture.fat")

    test "${first_elf%% *}" = "${second_elf%% *}"
    test "${first_disk%% *}" = "${second_disk%% *}"
    printf '%s\n%s\n' "$second_elf" "$second_disk"
done

echo 'FLYOLOGY:M6:REPRODUCIBLE:PASS'
