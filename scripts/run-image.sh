#!/bin/sh
set -eu

test "$#" -eq 3 || {
    echo "usage: $0 x86_64|aarch64 1|4 tasking|preemptive-fifo|preemptive-round-robin|domains" >&2
    exit 64
}

architecture=$1
cpu_count=$2
profile=$3
case "$cpu_count" in
    1|4) ;;
    *) echo "unsupported CPU count: $cpu_count" >&2; exit 64 ;;
esac
case "$profile" in
    tasking|preemptive-fifo|preemptive-round-robin|domains) ;;
    *) echo "unsupported image profile: $profile" >&2; exit 64 ;;
esac

test_tag=${FLYOLOGY_FREESTANDING_IMAGE_TEST_TAG:-gate}
case "$test_tag" in
    *[!A-Za-z0-9_.-]*) echo "invalid test tag: $test_tag" >&2; exit 64 ;;
esac
test_root=${FLYOLOGY_FREESTANDING_IMAGE_TEST_ROOT:-build/product/tests}
test_directory="$test_root/$architecture-smp$cpu_count-$profile-$test_tag"
mkdir -p "$test_directory"
output_root=${FLYOLOGY_FREESTANDING_IMAGE_OUTPUT_ROOT:-build/product/$profile}
image="$output_root/$architecture/flyology-freestanding-$architecture.fat"
serial_log="$test_directory/serial.log"
qemu_log="$test_directory/qemu.log"
: >"$serial_log"
: >"$qemu_log"
FLYOLOGY_FREESTANDING_QEMU_SERIAL="file:$serial_log" \
FLYOLOGY_FREESTANDING_QEMU_LOG="$qemu_log" \
FLYOLOGY_FREESTANDING_QEMU_TIMEOUT_SECONDS=20 \
    scripts/run-uefi-image.sh \
    "$architecture" "$cpu_count" "$image" "$test_directory"

count_marker() {
    marker=$1
    grep -aFo "$marker" "$serial_log" | wc -l | tr -d ' '
}

test "$(count_marker 'FLYOLOGY:ADA:ELABORATION:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:ADA:MAIN:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:FINALIZATION:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:TASKING:BOOT_SUBSTRATE:PASS')" -eq 1
if test "$profile" != domains; then
test "$(count_marker 'FLYOLOGY:TASKING:ORDINARY_TASKS:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:TASKING:SPECIFIC_CPU:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:TASKING:AUTO_MASTER:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:RECLAMATION:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:DELAYS:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:ABSOLUTE_DELAY:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:PROTECTED:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:PROTECTED_ENTRY:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:RENDEZVOUS:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:EXCEPTIONAL_SYNC:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:EXCEPTIONAL_PROTECTED_IMMEDIATE:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:EXCEPTIONAL_PROTECTED_QUEUED:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:EXCEPTION_ABORT_PROTECTED:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:EXCEPTIONAL_RENDEZVOUS:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:EXCEPTION_ABORT:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:UNACTIVATED_CLEANUP:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:ALLOCATOR_TARGET:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:DYNAMIC_PRIORITY:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:CEILING:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:CONDITIONAL_ENTRY:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:TIMED_ENTRY:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:DYNAMIC_TASK:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:FREE_TASK:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:FREE_TASK_WAIT:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:FREE_TASK_ABORT_RACE:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:SELECTIVE_WAIT:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:TERMINATE_ALTERNATIVE:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:ABORT:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:MULTI_ABORT:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:DEPENDENT_ABORT:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:ABORT_RENDEZVOUS:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:ABORT_TIMEOUT:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:ABORT_ACCEPTED:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:ABORT_PROTECTED:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:RTS:COLLISION_STRESS:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:TASKING:NESTED_MASTER:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:TASKING:TASK_STACKS:PASS')" -eq 1
if test "$cpu_count" -eq 4; then
    test "$(count_marker 'FLYOLOGY:TASKING:AUTO_PARALLEL:PASS')" -eq 1
else
    test "$(count_marker 'FLYOLOGY:TASKING:AUTO_PARALLEL:PASS')" -eq 0
fi
fi

test "$(count_marker 'FLYOLOGY:FAIL:')" -eq 0
test "$(count_marker 'PANIC:')" -eq 0
test "$(count_marker 'FLYOLOGY:CORE:ONLINE:')" -eq "$cpu_count"

core=0
while test "$core" -lt "$cpu_count"; do
    test "$(count_marker "FLYOLOGY:CORE:ONLINE:$core")" -eq 1
    core=$((core + 1))
done

case "$profile" in
    tasking) ;;
    preemptive-fifo|preemptive-round-robin)
        test "$(count_marker 'FLYOLOGY:PREEMPTION:FIFO_PREEMPTION:PASS')" -eq 1
        if test "$profile" = preemptive-round-robin; then
            test "$(count_marker 'FLYOLOGY:PREEMPTION:ROUND_ROBIN:PASS')" -eq 1
            test "$(count_marker 'FLYOLOGY:PREEMPTION:FIFO_NO_ROTATION:PASS')" -eq 0
        else
            test "$(count_marker 'FLYOLOGY:PREEMPTION:ROUND_ROBIN:PASS')" -eq 0
            test "$(count_marker 'FLYOLOGY:PREEMPTION:FIFO_NO_ROTATION:PASS')" -eq 1
        fi
        if test "$cpu_count" -eq 4; then
            test "$(count_marker 'FLYOLOGY:PREEMPTION:REMOTE_PREEMPTION:PASS')" -eq 1
            test "$(count_marker 'FLYOLOGY:PREEMPTION:ALL_CORE_PREEMPTION:PASS')" -eq 1
            test "$(count_marker 'FLYOLOGY:PREEMPTION:PRIORITY_REQUEUE:PASS')" -eq 1
            test "$(count_marker 'FLYOLOGY:PREEMPTION:NONBLOCKING_INGRESS:PASS')" -eq 1
        else
            test "$(count_marker 'FLYOLOGY:PREEMPTION:REMOTE_PREEMPTION:PASS')" -eq 0
            test "$(count_marker 'FLYOLOGY:PREEMPTION:ALL_CORE_PREEMPTION:PASS')" -eq 0
            test "$(count_marker 'FLYOLOGY:PREEMPTION:PRIORITY_REQUEUE:PASS')" -eq 0
            test "$(count_marker 'FLYOLOGY:PREEMPTION:NONBLOCKING_INGRESS:PASS')" -eq 0
        fi
        ;;
    domains)
        test "$(count_marker 'FLYOLOGY:DOMAINS:DOMAIN_LAYOUT:PASS')" -eq 1
        test "$(count_marker 'FLYOLOGY:DOMAINS:STANDARD_QUERIES:PASS')" -eq 1
        test "$(count_marker 'FLYOLOGY:SCHEDULING:LIVE_POLICY:PASS')" -eq 1
        test "$(count_marker 'FLYOLOGY:SCHEDULING:LIVE_EXECUTION:PASS')" -eq 1
        if test "$cpu_count" -eq 4; then
            test "$(count_marker 'FLYOLOGY:DOMAINS:DOMAIN_INHERITANCE:PASS')" -eq 1
            test "$(count_marker 'FLYOLOGY:DOMAINS:HETEROGENEOUS_POLICY:PASS')" -eq 1
            test "$(count_marker 'FLYOLOGY:DOMAINS:ALL_CORE_PREEMPTION:PASS')" -eq 1
        else
            test "$(count_marker 'FLYOLOGY:DOMAINS:DOMAIN_INHERITANCE:PASS')" -eq 0
            test "$(count_marker 'FLYOLOGY:DOMAINS:HETEROGENEOUS_POLICY:PASS')" -eq 0
            test "$(count_marker 'FLYOLOGY:DOMAINS:ALL_CORE_PREEMPTION:PASS')" -eq 0
        fi
        ;;
esac

echo "FLYOLOGY:IMAGE:RUN:PASS:$architecture:SMP$cpu_count:$profile"
