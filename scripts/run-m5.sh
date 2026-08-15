#!/bin/sh
set -eu

test "$#" -eq 3 || {
    echo "usage: $0 x86_64|aarch64 1|4 fifo|round_robin" >&2
    exit 64
}

architecture=$1
cpu_count=$2
policy=$3
case "$architecture" in
    x86_64|aarch64) ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac
case "$cpu_count" in
    1|4) ;;
    *) echo "unsupported CPU count: $cpu_count" >&2; exit 64 ;;
esac
case "$policy" in
    fifo|round_robin) ;;
    *) echo "unsupported M5 policy: $policy" >&2; exit 64 ;;
esac

gate_tag=${FLYOLOGY_M5_TEST_TAG:-gate}
output_base=${FLYOLOGY_M5_OUTPUT_ROOT:-build/m5}
case "$gate_tag" in
    *[!A-Za-z0-9_.-]*) echo "invalid M5 test tag: $gate_tag" >&2; exit 64 ;;
esac
output_root=${FLYOLOGY_M5_IMAGE_ROOT:-"$output_base/$policy"}

case "$policy" in
    fifo) profile=preemptive-fifo ;;
    round_robin) profile=preemptive-round-robin ;;
esac

FLYOLOGY_IMAGE_OUTPUT_ROOT="$output_root" \
FLYOLOGY_IMAGE_TEST_ROOT=build/m3/tests \
FLYOLOGY_IMAGE_TEST_TAG="m5-$policy-$gate_tag" \
    scripts/run-image.sh "$architecture" "$cpu_count" "$profile"

echo "FLYOLOGY:M5:BOOT_TEST:PASS:$architecture:SMP$cpu_count:$policy"
