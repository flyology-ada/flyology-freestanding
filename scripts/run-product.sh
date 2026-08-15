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
    tasking|preemptive-fifo|preemptive-round-robin|domains) ;;
    *) echo "unsupported product profile: $profile" >&2; exit 64 ;;
esac

FLYOLOGY_IMAGE_OUTPUT_ROOT="$image_root" \
FLYOLOGY_IMAGE_TEST_TAG="$tag" \
    scripts/run-image.sh "$architecture" "$cpu_count" "$profile"

echo "FLYOLOGY:PRODUCT:RUN:PASS:$architecture:SMP$cpu_count:$profile"
