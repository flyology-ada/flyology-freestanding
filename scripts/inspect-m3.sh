#!/bin/sh
set -eu

test "$#" -eq 1 || {
    echo "usage: $0 x86_64|aarch64" >&2
    exit 64
}

FLYOLOGY_IMAGE_OUTPUT_ROOT="${FLYOLOGY_M3_OUTPUT_ROOT:-build/m3}" \
    scripts/inspect-image.sh "$1" tasking

echo "FLYOLOGY:M3:INSPECT:PASS:$1"
