#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/test-tasking-models.sh
scripts/test-synchronization-models.sh
scripts/test-allocator.sh
scripts/test-abort-exception.sh
scripts/probe-tasking-interface.sh
scripts/probe-synchronization-interface.sh
scripts/check-interrupt-layout.sh
for architecture in x86_64 aarch64; do
    scripts/build-exception-probe.sh "$architecture"
    scripts/run-exception-probe.sh "$architecture" 1
    scripts/run-exception-probe.sh "$architecture" 4
done
scripts/verify-tasking-reproducible.sh
for architecture in x86_64 aarch64; do
    scripts/build-product.sh "$architecture" tasking >/dev/null
    FLYOLOGY_IMAGE_OUTPUT_ROOT=build/product/tasking \
        scripts/inspect-image.sh "$architecture" tasking
    FLYOLOGY_IMAGE_OUTPUT_ROOT=build/product/tasking \
        scripts/check-unwind.sh "$architecture"
    FLYOLOGY_PRODUCT_TEST_TAG=synchronization-gate \
        scripts/run-product.sh "$architecture" 1 tasking
    FLYOLOGY_PRODUCT_TEST_TAG=synchronization-gate \
        scripts/run-product.sh "$architecture" 4 tasking
done
scripts/stress-synchronization.sh

echo 'FLYOLOGY:RTS:GATE:PASS'
