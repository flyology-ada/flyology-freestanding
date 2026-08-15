#!/bin/sh
set -eu

first=build/reproducible/domains-first
second=build/reproducible/domains-second

for architecture in x86_64 aarch64; do
    FLYOLOGY_FREESTANDING_PRODUCT_OUTPUT_ROOT=$first \
        scripts/build-product.sh "$architecture" domains >/dev/null
    FLYOLOGY_FREESTANDING_PRODUCT_OUTPUT_ROOT=$second \
        scripts/build-product.sh "$architecture" domains >/dev/null

    first_elf=$(shasum -a 256 "$first/domains/$architecture/flyology-freestanding.elf")
    second_elf=$(shasum -a 256 "$second/domains/$architecture/flyology-freestanding.elf")
    first_disk=$(shasum -a 256 \
        "$first/domains/$architecture/flyology-freestanding-$architecture.fat")
    second_disk=$(shasum -a 256 \
        "$second/domains/$architecture/flyology-freestanding-$architecture.fat")

    test "${first_elf%% *}" = "${second_elf%% *}"
    test "${first_disk%% *}" = "${second_disk%% *}"
    printf '%s\n%s\n' "$second_elf" "$second_disk"
done

echo 'FLYOLOGY:DOMAINS:REPRODUCIBLE:PASS'
