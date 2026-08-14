#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/test-m3-models.sh
scripts/test-m4-models.sh
scripts/test-m5-policy.sh
scripts/test-m4-allocator.sh
scripts/test-m4-abort-exception.sh
scripts/probe-m3-interface.sh
scripts/probe-m4-interface.sh
scripts/probe-m5-policy.sh
scripts/check-m2-layout.sh
scripts/verify-m5-reproducible.sh

for policy in fifo round_robin; do
    for architecture in x86_64 aarch64; do
        scripts/build-m5.sh "$architecture" "$policy" >/dev/null
        scripts/inspect-m5.sh "$architecture" "$policy"
        FLYOLOGY_M3_OUTPUT_ROOT="build/m5/$policy" \
            scripts/check-m4-unwind.sh "$architecture"
    done
done

for policy in fifo round_robin; do
    for architecture in x86_64 aarch64; do
        scripts/run-m5.sh "$architecture" 1 "$policy"
        scripts/run-m5.sh "$architecture" 4 "$policy"
    done
done

scripts/stress-m5.sh

echo 'FLYOLOGY:M5:GATE:PASS'
