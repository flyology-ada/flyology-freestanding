#!/bin/sh
set -eu

test "$#" -eq 2 || {
    echo "usage: $0 x86_64|aarch64 1|4" >&2
    exit 64
}

FLYOLOGY_IMAGE_OUTPUT_ROOT="${FLYOLOGY_M3_OUTPUT_ROOT:-build/m3}" \
FLYOLOGY_IMAGE_TEST_ROOT=build/m3/tests \
FLYOLOGY_IMAGE_TEST_TAG="${FLYOLOGY_M3_TEST_TAG:-gate}" \
    scripts/run-image.sh "$1" "$2" tasking

echo "FLYOLOGY:M3:BOOT_TEST:PASS:$1:SMP$2"
