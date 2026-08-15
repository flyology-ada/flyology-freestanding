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

output_root=${FLYOLOGY_FREESTANDING_PRODUCT_OUTPUT_ROOT:-build/product}
if test "${FLYOLOGY_FREESTANDING_FLAT_OUTPUT:-0}" = 1; then
    profile_root=$output_root
else
    profile_root="$output_root/$profile"
fi

case "$profile" in
    tasking)
        FLYOLOGY_FREESTANDING_IMAGE_OUTPUT_ROOT="$profile_root" \
            scripts/build-image.sh "$architecture"
        ;;
    preemptive-fifo)
        FLYOLOGY_FREESTANDING_PRODUCT_CONFIG=config/scheduler/fifo.adc \
        FLYOLOGY_FREESTANDING_BINDER_FLAGS=-T0 \
        FLYOLOGY_FREESTANDING_IMAGE_OUTPUT_ROOT="$profile_root" \
            scripts/build-image.sh "$architecture"
        ;;
    preemptive-round-robin)
        FLYOLOGY_FREESTANDING_PRODUCT_CONFIG=config/scheduler/round_robin.adc \
        FLYOLOGY_FREESTANDING_BINDER_FLAGS=-T10 \
        FLYOLOGY_FREESTANDING_IMAGE_OUTPUT_ROOT="$profile_root" \
            scripts/build-image.sh "$architecture"
        ;;
    domains)
        FLYOLOGY_FREESTANDING_DOMAINS=1 \
        FLYOLOGY_FREESTANDING_PRODUCT_CONFIG=config/scheduler/fifo.adc \
        FLYOLOGY_FREESTANDING_DOMAIN_CONFIG_DIR=config/domains/on \
        FLYOLOGY_FREESTANDING_CONFORMANCE_CONFIG_DIR=tests/target/config/domains/on \
        FLYOLOGY_FREESTANDING_BINDER_FLAGS=-T0 \
        FLYOLOGY_FREESTANDING_IMAGE_OUTPUT_ROOT="$profile_root" \
            scripts/build-image.sh "$architecture"
        ;;
    *) echo "unsupported product profile: $profile" >&2; exit 64 ;;
esac

echo "FLYOLOGY:PRODUCT:BUILD:PASS:$architecture:$profile"
