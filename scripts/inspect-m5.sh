#!/bin/sh
set -eu

test "$#" -eq 2 || {
    echo "usage: $0 x86_64|aarch64 fifo|round_robin" >&2
    exit 64
}

architecture=$1
policy=$2
output_base=${FLYOLOGY_M5_OUTPUT_ROOT:-build/m5}
case "$architecture" in
    x86_64) target=x86_64-elf ;;
    aarch64) target=aarch64-elf ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac
case "$policy" in
    fifo)
        policy_character=F
        time_slice=0
        ;;
    round_robin)
        policy_character=R
        time_slice=10000
        ;;
    *) echo "unsupported M5 policy: $policy" >&2; exit 64 ;;
esac

output_root="$output_base/$policy"
FLYOLOGY_M3_OUTPUT_ROOT="$output_root" scripts/inspect-m3.sh "$architecture"

elf="$output_root/$architecture/flyology-m3.elf"
binder="$output_root/$architecture/b~flyology_conformance.adb"
nm_output=$(scripts/toolchain.sh exec "$architecture" "$target-nm" -n "$elf")

for symbol in flyology_m5_interrupt_dispatch \
    flyology_m5_preemption_canary \
    flyology_m5_retry_interrupt flyology_m5_retry_count \
    flyology_rts_lock_try_acquire \
    flyology_context_switch_to_task flyology_context_switch_to_full \
    flyology__platform__capture_full_context \
    flyology__preemption_model__configuration_is_valid \
    flyology__preemption_model__quantum_ticks \
    flyology__preemption_model__account \
    flyology__preemption_model__decide \
    __gl_time_slice_val __gl_task_dispatching_policy; do
    printf '%s\n' "$nm_output" | grep -E "[[:space:]]$symbol$" >/dev/null
done

grep -F "Time_Slice_Value := $time_slice;" "$binder" >/dev/null
grep -F "Task_Dispatching_Policy := '$policy_character';" "$binder" >/dev/null

strings_output=$(scripts/toolchain.sh exec \
    "$architecture" "$target-strings" "$elf")
printf '%s\n' "$strings_output" | \
    grep -F 'FLYOLOGY:M5:FIFO_PREEMPTION:PASS' >/dev/null
printf '%s\n' "$strings_output" | \
    grep -F 'FLYOLOGY:M5:ROUND_ROBIN:PASS' >/dev/null
printf '%s\n' "$strings_output" | \
    grep -F 'FLYOLOGY:M5:REMOTE_PREEMPTION:PASS' >/dev/null
printf '%s\n' "$strings_output" | \
    grep -F 'FLYOLOGY:M5:ALL_CORE_PREEMPTION:PASS' >/dev/null
printf '%s\n' "$strings_output" | \
    grep -F 'FLYOLOGY:M5:FIFO_NO_ROTATION:PASS' >/dev/null
printf '%s\n' "$strings_output" | \
    grep -F 'FLYOLOGY:M5:PRIORITY_REQUEUE:PASS' >/dev/null
printf '%s\n' "$strings_output" | \
    grep -F 'FLYOLOGY:M5:NONBLOCKING_INGRESS:PASS' >/dev/null

echo "FLYOLOGY:M5:INSPECT:PASS:$architecture:$policy"
