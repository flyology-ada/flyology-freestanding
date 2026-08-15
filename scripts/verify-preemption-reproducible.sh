#!/bin/sh
set -eu

first=build/reproducible/preemption-first
second=build/reproducible/preemption-second

for policy in fifo round_robin; do
    for architecture in x86_64 aarch64; do
        case "$policy" in
            fifo) profile=preemptive-fifo ;;
            round_robin) profile=preemptive-round-robin ;;
        esac
        FLYOLOGY_FREESTANDING_PRODUCT_OUTPUT_ROOT=$first \
            scripts/build-product.sh "$architecture" "$profile" >/dev/null
        FLYOLOGY_FREESTANDING_PRODUCT_OUTPUT_ROOT=$second \
            scripts/build-product.sh "$architecture" "$profile" >/dev/null

        first_elf=$(shasum -a 256 \
            "$first/$profile/$architecture/flyology-freestanding.elf")
        second_elf=$(shasum -a 256 \
            "$second/$profile/$architecture/flyology-freestanding.elf")
        first_disk=$(shasum -a 256 \
            "$first/$profile/$architecture/flyology-freestanding-$architecture.fat")
        second_disk=$(shasum -a 256 \
            "$second/$profile/$architecture/flyology-freestanding-$architecture.fat")

        test "${first_elf%% *}" = "${second_elf%% *}"
        test "${first_disk%% *}" = "${second_disk%% *}"
        printf '%s\n%s\n' "$second_elf" "$second_disk"
    done
done

echo 'FLYOLOGY:PREEMPTION:REPRODUCIBLE:PASS'
