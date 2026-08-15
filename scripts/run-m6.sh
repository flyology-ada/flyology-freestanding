#!/bin/sh
set -eu

test "$#" -eq 2 || {
    echo "usage: $0 x86_64|aarch64 1|4" >&2
    exit 64
}

architecture=$1
cpu_count=$2
case "$architecture" in
    x86_64|aarch64) ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac
case "$cpu_count" in
    1|4) ;;
    *) echo "unsupported CPU count: $cpu_count" >&2; exit 64 ;;
esac

gate_tag=${FLYOLOGY_M6_TEST_TAG:-gate}
output_root=${FLYOLOGY_M6_OUTPUT_ROOT:-build/m6}
case "$gate_tag" in
    *[!A-Za-z0-9_.-]*) echo "invalid M6 test tag: $gate_tag" >&2; exit 64 ;;
esac
FLYOLOGY_IMAGE_OUTPUT_ROOT="$output_root" \
FLYOLOGY_IMAGE_TEST_ROOT=build/m3/tests \
FLYOLOGY_IMAGE_TEST_TAG="m6-$gate_tag" \
    scripts/run-image.sh "$architecture" "$cpu_count" domains

echo "FLYOLOGY:M6:BOOT_TEST:PASS:$architecture:SMP$cpu_count"
