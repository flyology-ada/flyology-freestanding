#!/bin/sh
set -eu

test "$#" -eq 3 || {
    echo "usage: $0 x86_64|aarch64 1|4 tasking|preemptive-fifo|preemptive-round-robin|domains" >&2
    exit 64
}

architecture=$1
cpu_count=$2
profile=$3
output_root=${FLYOLOGY_PRODUCT_OUTPUT_ROOT:-build/product}
image_root="$output_root/$profile"
tag=${FLYOLOGY_PRODUCT_TEST_TAG:-gate}

case "$profile" in
    tasking)
        FLYOLOGY_M3_OUTPUT_ROOT="$image_root" \
        FLYOLOGY_M3_TEST_TAG="product-tasking-$tag" \
            scripts/run-m3.sh "$architecture" "$cpu_count"
        ;;
    preemptive-fifo)
        FLYOLOGY_M5_IMAGE_ROOT="$image_root" \
        FLYOLOGY_M5_TEST_TAG="product-fifo-$tag" \
            scripts/run-m5.sh "$architecture" "$cpu_count" fifo
        ;;
    preemptive-round-robin)
        FLYOLOGY_M5_IMAGE_ROOT="$image_root" \
        FLYOLOGY_M5_TEST_TAG="product-round-robin-$tag" \
            scripts/run-m5.sh "$architecture" "$cpu_count" round_robin
        ;;
    domains)
        FLYOLOGY_M6_OUTPUT_ROOT="$image_root" \
        FLYOLOGY_M6_TEST_TAG="product-domains-$tag" \
            scripts/run-m6.sh "$architecture" "$cpu_count"
        ;;
    *) echo "unsupported product profile: $profile" >&2; exit 64 ;;
esac

echo "FLYOLOGY:PRODUCT:RUN:PASS:$architecture:SMP$cpu_count:$profile"
