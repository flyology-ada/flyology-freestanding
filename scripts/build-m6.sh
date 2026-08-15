#!/bin/sh
set -eu

test "$#" -eq 1 || {
    echo "usage: $0 x86_64|aarch64" >&2
    exit 64
}

architecture=$1
case "$architecture" in
    x86_64|aarch64) ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

FLYOLOGY_PREEMPTION=1 \
FLYOLOGY_DOMAINS=1 \
FLYOLOGY_PRODUCT_CONFIG=config/scheduler/fifo.adc \
FLYOLOGY_SCHEDULER_CONFIG_DIR=config/scheduler/fifo \
FLYOLOGY_DOMAIN_CONFIG_DIR=config/domains/on \
FLYOLOGY_CONFORMANCE_CONFIG_DIR=tests/target/config/domains/on \
FLYOLOGY_BINDER_FLAGS=-T0 \
FLYOLOGY_IMAGE_OUTPUT_ROOT="${FLYOLOGY_M6_OUTPUT_ROOT:-build/m6}" \
    scripts/build-image.sh "$architecture"
