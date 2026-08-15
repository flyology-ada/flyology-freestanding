#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/test-tasking-models.sh
scripts/probe-tasking-interface.sh
scripts/probe-synchronization-interface.sh
scripts/check-interrupt-layout.sh
scripts/verify-tasking-reproducible.sh
for architecture in x86_64 aarch64; do
    scripts/build-product.sh "$architecture" tasking >/dev/null
    FLYOLOGY_FREESTANDING_IMAGE_OUTPUT_ROOT=build/product/tasking \
        scripts/inspect-image.sh "$architecture" tasking
    scripts/run-product.sh "$architecture" 1 tasking
    scripts/run-product.sh "$architecture" 4 tasking
done
scripts/stress-tasking.sh

echo 'FLYOLOGY:TASKING:GATE:PASS'
