#!/bin/sh
set -eu

test "$#" -eq 2 || {
    echo "usage: $0 x86_64|aarch64 fifo|round_robin" >&2
    exit 64
}

architecture=$1
policy=$2
output_base=${FLYOLOGY_PREEMPTION_OUTPUT_ROOT:-build/preemption}
case "$policy" in
    fifo)
        config=config/scheduler/fifo.adc
        config_dir=config/scheduler/fifo
        binder_flags=-T0
        ;;
    round_robin)
        config=config/scheduler/round_robin.adc
        config_dir=config/scheduler/round_robin
        binder_flags=-T10
        ;;
    *) echo "unsupported preemption policy: $policy" >&2; exit 64 ;;
esac

FLYOLOGY_PREEMPTION=1 \
FLYOLOGY_PRODUCT_CONFIG=$config \
FLYOLOGY_SCHEDULER_CONFIG_DIR=$config_dir \
FLYOLOGY_BINDER_FLAGS=$binder_flags \
FLYOLOGY_IMAGE_OUTPUT_ROOT="$output_base/$policy" \
    scripts/build-image.sh "$architecture"
