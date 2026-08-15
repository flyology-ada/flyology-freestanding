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
        FLYOLOGY_IMAGE_OUTPUT_ROOT="$profile_root" \
            scripts/build-image.sh "$architecture"
        ;;
    preemptive-fifo)
        FLYOLOGY_PREEMPTION=1 \
        FLYOLOGY_PRODUCT_CONFIG=config/scheduler/fifo.adc \
        FLYOLOGY_SCHEDULER_CONFIG_DIR=config/scheduler/fifo \
        FLYOLOGY_BINDER_FLAGS=-T0 \
        FLYOLOGY_IMAGE_OUTPUT_ROOT="$profile_root" \
            scripts/build-image.sh "$architecture"
        ;;
    preemptive-round-robin)
        FLYOLOGY_PREEMPTION=1 \
        FLYOLOGY_PRODUCT_CONFIG=config/scheduler/round_robin.adc \
        FLYOLOGY_SCHEDULER_CONFIG_DIR=config/scheduler/round_robin \
        FLYOLOGY_BINDER_FLAGS=-T10 \
        FLYOLOGY_IMAGE_OUTPUT_ROOT="$profile_root" \
            scripts/build-image.sh "$architecture"
        ;;
    domains)
        FLYOLOGY_PREEMPTION=1 \
        FLYOLOGY_DOMAINS=1 \
        FLYOLOGY_PRODUCT_CONFIG=config/scheduler/fifo.adc \
        FLYOLOGY_SCHEDULER_CONFIG_DIR=config/scheduler/fifo \
        FLYOLOGY_DOMAIN_CONFIG_DIR=config/domains/on \
        FLYOLOGY_CONFORMANCE_CONFIG_DIR=tests/target/config/domains/on \
        FLYOLOGY_BINDER_FLAGS=-T0 \
        FLYOLOGY_IMAGE_OUTPUT_ROOT="$profile_root" \
            scripts/build-image.sh "$architecture"
        ;;
    *) echo "unsupported product profile: $profile" >&2; exit 64 ;;
esac

echo "FLYOLOGY:PRODUCT:BUILD:PASS:$architecture:$profile"
