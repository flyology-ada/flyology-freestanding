#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/test-tasking-models.sh
scripts/test-synchronization-models.sh
scripts/test-preemption-policy.sh
scripts/test-allocator.sh
scripts/test-abort-exception.sh
scripts/probe-tasking-interface.sh
scripts/probe-synchronization-interface.sh
scripts/probe-preemption-policy.sh
scripts/check-interrupt-layout.sh
scripts/verify-preemption-reproducible.sh

for policy in fifo round_robin; do
    for architecture in x86_64 aarch64; do
        scripts/build-preemption-image.sh "$architecture" "$policy" >/dev/null
        case "$policy" in
            fifo) profile=preemptive-fifo ;;
            round_robin) profile=preemptive-round-robin ;;
        esac
        FLYOLOGY_IMAGE_OUTPUT_ROOT="build/preemption/$policy" \
            scripts/inspect-image.sh "$architecture" "$profile"
        FLYOLOGY_IMAGE_OUTPUT_ROOT="build/preemption/$policy" \
            scripts/check-unwind.sh "$architecture"
    done
done

for policy in fifo round_robin; do
    for architecture in x86_64 aarch64; do
        case "$policy" in
            fifo) profile=preemptive-fifo ;;
            round_robin) profile=preemptive-round-robin ;;
        esac
        FLYOLOGY_IMAGE_OUTPUT_ROOT="build/preemption/$policy" \
            scripts/run-image.sh "$architecture" 1 "$profile"
        FLYOLOGY_IMAGE_OUTPUT_ROOT="build/preemption/$policy" \
            scripts/run-image.sh "$architecture" 4 "$profile"
    done
done

scripts/stress-preemption.sh

echo 'FLYOLOGY:PREEMPTION:GATE:PASS'
