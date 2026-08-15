#!/bin/sh
set -eu

first=build/reproducible/preemption-first
second=build/reproducible/preemption-second

for policy in fifo round_robin; do
    for architecture in x86_64 aarch64; do
        FLYOLOGY_PREEMPTION_OUTPUT_ROOT=$first \
            scripts/build-preemption-image.sh "$architecture" "$policy" >/dev/null
        FLYOLOGY_PREEMPTION_OUTPUT_ROOT=$second \
            scripts/build-preemption-image.sh "$architecture" "$policy" >/dev/null

        first_elf=$(shasum -a 256 \
            "$first/$policy/$architecture/flyology.elf")
        second_elf=$(shasum -a 256 \
            "$second/$policy/$architecture/flyology.elf")
        first_disk=$(shasum -a 256 \
            "$first/$policy/$architecture/flyology-$architecture.fat")
        second_disk=$(shasum -a 256 \
            "$second/$policy/$architecture/flyology-$architecture.fat")

        test "${first_elf%% *}" = "${second_elf%% *}"
        test "${first_disk%% *}" = "${second_disk%% *}"
        printf '%s\n%s\n' "$second_elf" "$second_disk"
    done
done

echo 'FLYOLOGY:PREEMPTION:REPRODUCIBLE:PASS'
