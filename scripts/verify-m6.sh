#!/bin/sh
set -eu

scripts/verify-formal-models.sh
scripts/test-m4-allocator.sh
scripts/test-m4-abort-exception.sh
scripts/probe-m3-interface.sh
scripts/probe-m4-interface.sh
scripts/probe-m5-policy.sh
scripts/probe-m6-interface.sh
scripts/check-m2-layout.sh
scripts/verify-m6-reproducible.sh

for architecture in x86_64 aarch64; do
    scripts/build-m6.sh "$architecture" >/dev/null
    scripts/inspect-m6.sh "$architecture"
    FLYOLOGY_M3_OUTPUT_ROOT=build/m6 FLYOLOGY_UNWIND_PROFILE=m6 \
        scripts/check-m4-unwind.sh "$architecture"
done

for architecture in x86_64 aarch64; do
    scripts/run-m6.sh "$architecture" 1
    scripts/run-m6.sh "$architecture" 4
done

scripts/stress-m6.sh

echo 'FLYOLOGY:M6:GATE:PASS'
