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
scripts/verify-tasking-reproducible.sh
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/build-image.sh x86_64 >/dev/null
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/build-image.sh aarch64 >/dev/null
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/inspect-image.sh x86_64 tasking
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/inspect-image.sh aarch64 tasking
scripts/check-unwind.sh x86_64
scripts/check-unwind.sh aarch64
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking \
FLYOLOGY_IMAGE_TEST_TAG=synchronization-gate \
    scripts/run-image.sh x86_64 1 tasking
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking \
FLYOLOGY_IMAGE_TEST_TAG=synchronization-gate \
    scripts/run-image.sh x86_64 4 tasking
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking \
FLYOLOGY_IMAGE_TEST_TAG=synchronization-gate \
    scripts/run-image.sh aarch64 1 tasking
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking \
FLYOLOGY_IMAGE_TEST_TAG=synchronization-gate \
    scripts/run-image.sh aarch64 4 tasking
scripts/stress-synchronization.sh

echo 'FLYOLOGY:RTS:GATE:PASS'
