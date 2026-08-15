#!/bin/sh
set -eu

first=build/reproducible/tasking-first
second=build/reproducible/tasking-second

for architecture in x86_64 aarch64; do
    FLYOLOGY_PRODUCT_OUTPUT_ROOT=$first \
        scripts/build-product.sh "$architecture" tasking >/dev/null
    FLYOLOGY_PRODUCT_OUTPUT_ROOT=$second \
        scripts/build-product.sh "$architecture" tasking >/dev/null

    first_elf=$(shasum -a 256 "$first/tasking/$architecture/flyology.elf")
    second_elf=$(shasum -a 256 "$second/tasking/$architecture/flyology.elf")
    first_disk=$(shasum -a 256 \
        "$first/tasking/$architecture/flyology-$architecture.fat")
    second_disk=$(shasum -a 256 \
        "$second/tasking/$architecture/flyology-$architecture.fat")

    test "${first_elf%% *}" = "${second_elf%% *}"
    test "${first_disk%% *}" = "${second_disk%% *}"
    printf '%s\n%s\n' "$second_elf" "$second_disk"
done

echo 'FLYOLOGY:TASKING:REPRODUCIBLE:PASS'
