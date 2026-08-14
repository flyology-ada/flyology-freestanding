#!/bin/sh
set -eu

first=build/reproducible/m5-first
second=build/reproducible/m5-second

for policy in fifo round_robin; do
    for architecture in x86_64 aarch64; do
        FLYOLOGY_M5_OUTPUT_ROOT=$first \
            scripts/build-m5.sh "$architecture" "$policy" >/dev/null
        FLYOLOGY_M5_OUTPUT_ROOT=$second \
            scripts/build-m5.sh "$architecture" "$policy" >/dev/null

        first_elf=$(shasum -a 256 \
            "$first/$policy/$architecture/flyology-m3.elf")
        second_elf=$(shasum -a 256 \
            "$second/$policy/$architecture/flyology-m3.elf")
        first_disk=$(shasum -a 256 \
            "$first/$policy/$architecture/flyology-$architecture.fat")
        second_disk=$(shasum -a 256 \
            "$second/$policy/$architecture/flyology-$architecture.fat")

        test "${first_elf%% *}" = "${second_elf%% *}"
        test "${first_disk%% *}" = "${second_disk%% *}"
        printf '%s\n%s\n' "$second_elf" "$second_disk"
    done
done

echo 'FLYOLOGY:M5:REPRODUCIBLE:PASS'
