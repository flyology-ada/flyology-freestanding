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
test_tag="m6-$gate_tag"

FLYOLOGY_RUN_PROFILE=m6 \
FLYOLOGY_M3_OUTPUT_ROOT="$output_root" \
FLYOLOGY_M3_TEST_TAG="$test_tag" \
    scripts/run-m3.sh "$architecture" "$cpu_count"

serial_log="build/m3/tests/$architecture-smp$cpu_count-$test_tag/serial.log"
count_marker() {
    marker=$1
    grep -aFo "$marker" "$serial_log" | wc -l | tr -d ' '
}

test "$(count_marker 'FLYOLOGY:M6:DOMAIN_LAYOUT:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M6:STANDARD_QUERIES:PASS')" -eq 1
if test "$cpu_count" -eq 4; then
    test "$(count_marker 'FLYOLOGY:M6:DOMAIN_INHERITANCE:PASS')" -eq 1
    test "$(count_marker 'FLYOLOGY:M6:HETEROGENEOUS_POLICY:PASS')" -eq 1
    test "$(count_marker 'FLYOLOGY:M6:ALL_CORE_PREEMPTION:PASS')" -eq 1
else
    test "$(count_marker 'FLYOLOGY:M6:DOMAIN_INHERITANCE:PASS')" -eq 0
    test "$(count_marker 'FLYOLOGY:M6:HETEROGENEOUS_POLICY:PASS')" -eq 0
    test "$(count_marker 'FLYOLOGY:M6:ALL_CORE_PREEMPTION:PASS')" -eq 0
fi

echo "FLYOLOGY:M6:BOOT_TEST:PASS:$architecture:SMP$cpu_count"
