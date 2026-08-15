#!/bin/sh
set -eu

first=build/reproducible/domains-first
second=build/reproducible/domains-second

for architecture in x86_64 aarch64; do
    FLYOLOGY_DOMAIN_OUTPUT_ROOT=$first scripts/build-domain-image.sh "$architecture" >/dev/null
    FLYOLOGY_DOMAIN_OUTPUT_ROOT=$second scripts/build-domain-image.sh "$architecture" >/dev/null

    first_elf=$(shasum -a 256 "$first/$architecture/flyology.elf")
    second_elf=$(shasum -a 256 "$second/$architecture/flyology.elf")
    first_disk=$(shasum -a 256 "$first/$architecture/flyology-$architecture.fat")
    second_disk=$(shasum -a 256 "$second/$architecture/flyology-$architecture.fat")

    test "${first_elf%% *}" = "${second_elf%% *}"
    test "${first_disk%% *}" = "${second_disk%% *}"
    printf '%s\n%s\n' "$second_elf" "$second_disk"
done

echo 'FLYOLOGY:DOMAINS:REPRODUCIBLE:PASS'
