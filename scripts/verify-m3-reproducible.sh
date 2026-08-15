#!/bin/sh
set -eu

first=build/reproducible/m3-first
second=build/reproducible/m3-second

for architecture in x86_64 aarch64; do
    FLYOLOGY_IMAGE_OUTPUT_ROOT=$first scripts/build-image.sh "$architecture" >/dev/null
    FLYOLOGY_IMAGE_OUTPUT_ROOT=$second scripts/build-image.sh "$architecture" >/dev/null

    first_elf=$(shasum -a 256 "$first/$architecture/flyology-m3.elf")
    second_elf=$(shasum -a 256 "$second/$architecture/flyology-m3.elf")
    first_disk=$(shasum -a 256 "$first/$architecture/flyology-$architecture.fat")
    second_disk=$(shasum -a 256 "$second/$architecture/flyology-$architecture.fat")

    test "${first_elf%% *}" = "${second_elf%% *}"
    test "${first_disk%% *}" = "${second_disk%% *}"
    printf '%s\n%s\n' "$second_elf" "$second_disk"
done

echo 'FLYOLOGY:M3:REPRODUCIBLE:PASS'
