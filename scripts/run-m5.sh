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
test_tag="m5-$policy-$gate_tag"
output_root="$output_base/$policy"

FLYOLOGY_M3_OUTPUT_ROOT="$output_root" \
FLYOLOGY_M3_TEST_TAG="$test_tag" \
    scripts/run-m3.sh "$architecture" "$cpu_count"

serial_log="build/m3/tests/$architecture-smp$cpu_count-$test_tag/serial.log"
count_marker() {
    marker=$1
    grep -aFo "$marker" "$serial_log" | wc -l | tr -d ' '
}

test "$(count_marker 'FLYOLOGY:M5:FIFO_PREEMPTION:PASS')" -eq 1
if test "$policy" = round_robin; then
    test "$(count_marker 'FLYOLOGY:M5:ROUND_ROBIN:PASS')" -eq 1
    test "$(count_marker 'FLYOLOGY:M5:FIFO_NO_ROTATION:PASS')" -eq 0
else
    test "$(count_marker 'FLYOLOGY:M5:ROUND_ROBIN:PASS')" -eq 0
    test "$(count_marker 'FLYOLOGY:M5:FIFO_NO_ROTATION:PASS')" -eq 1
fi
if test "$cpu_count" -eq 4; then
    test "$(count_marker 'FLYOLOGY:M5:REMOTE_PREEMPTION:PASS')" -eq 1
    test "$(count_marker 'FLYOLOGY:M5:ALL_CORE_PREEMPTION:PASS')" -eq 1
    test "$(count_marker 'FLYOLOGY:M5:PRIORITY_REQUEUE:PASS')" -eq 1
    test "$(count_marker 'FLYOLOGY:M5:NONBLOCKING_INGRESS:PASS')" -eq 1
else
    test "$(count_marker 'FLYOLOGY:M5:REMOTE_PREEMPTION:PASS')" -eq 0
    test "$(count_marker 'FLYOLOGY:M5:ALL_CORE_PREEMPTION:PASS')" -eq 0
    test "$(count_marker 'FLYOLOGY:M5:PRIORITY_REQUEUE:PASS')" -eq 0
    test "$(count_marker 'FLYOLOGY:M5:NONBLOCKING_INGRESS:PASS')" -eq 0
fi

echo "FLYOLOGY:M5:BOOT_TEST:PASS:$architecture:SMP$cpu_count:$policy"
