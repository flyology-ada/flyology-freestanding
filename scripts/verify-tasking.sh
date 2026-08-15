#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/test-tasking-models.sh
scripts/probe-tasking-interface.sh
scripts/probe-synchronization-interface.sh
scripts/check-interrupt-layout.sh
scripts/verify-tasking-reproducible.sh
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/build-image.sh x86_64 >/dev/null
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/build-image.sh aarch64 >/dev/null
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/inspect-image.sh x86_64 tasking
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/inspect-image.sh aarch64 tasking
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/run-image.sh x86_64 1 tasking
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/run-image.sh x86_64 4 tasking
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/run-image.sh aarch64 1 tasking
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/tasking scripts/run-image.sh aarch64 4 tasking
scripts/stress-tasking.sh

echo 'FLYOLOGY:TASKING:GATE:PASS'
