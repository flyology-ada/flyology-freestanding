#!/bin/sh
set -eu

test "$#" -eq 2 || {
    echo "usage: $0 x86_64|aarch64 tasking|preemptive-fifo|preemptive-round-robin|domains" >&2
    exit 64
}

architecture=$1
profile=$2
case "$architecture" in
    x86_64|aarch64) ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

output_root=${FLYOLOGY_PRODUCT_OUTPUT_ROOT:-build/product}
profile_root="$output_root/$profile"

case "$profile" in
    tasking)
        FLYOLOGY_M3_OUTPUT_ROOT="$profile_root" \
            scripts/build-m3.sh "$architecture"
        ;;
    preemptive-fifo)
        FLYOLOGY_M5_OUTPUT_ROOT="$profile_root" \
            scripts/build-m5.sh "$architecture" fifo
        ;;
    preemptive-round-robin)
        FLYOLOGY_M5_OUTPUT_ROOT="$profile_root" \
            scripts/build-m5.sh "$architecture" round_robin
        ;;
    domains)
        FLYOLOGY_M6_OUTPUT_ROOT="$profile_root" \
            scripts/build-m6.sh "$architecture"
        ;;
    *) echo "unsupported product profile: $profile" >&2; exit 64 ;;
esac

architecture_root="$profile_root/$architecture"
cp "$architecture_root/flyology-m3.elf" "$architecture_root/flyology.elf"
echo "FLYOLOGY:PRODUCT:BUILD:PASS:$architecture:$profile"
