#!/bin/sh
set -eu

test "$#" -eq 1 || {
    echo "usage: $0 x86_64|aarch64" >&2
    exit 64
}

architecture=$1
case "$architecture" in
    x86_64)
        target=x86_64-elf
        machine='Advanced Micro Devices X86-64'
        reschedule=RESCHEDULE_IPI
        ;;
    aarch64)
        target=aarch64-elf
        machine='AArch64'
        reschedule=RESCHEDULE_SGI
        ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

elf="build/m2/$architecture/flyology-m2.elf"
test -f "$elf" || {
    echo "missing M2 ELF: $elf" >&2
    exit 66
}

readelf_output=$(scripts/toolchain.sh exec "$architecture" \
    "$target-readelf" -h -l -S -r "$elf")
program_output=$(scripts/toolchain.sh exec "$architecture" \
    "$target-readelf" -l "$elf")
nm_output=$(scripts/toolchain.sh exec "$architecture" "$target-nm" -n "$elf")

printf '%s\n' "$readelf_output" | grep -F 'Class:                             ELF64' >/dev/null
printf '%s\n' "$readelf_output" | grep -F 'Type:                              EXEC (Executable file)' >/dev/null
printf '%s\n' "$readelf_output" | grep -F "Machine:                           $machine" >/dev/null
printf '%s\n' "$readelf_output" | grep -F 'Entry point address:               0xffffffff80000000' >/dev/null
printf '%s\n' "$readelf_output" | grep -F 'There are no relocations in this file.' >/dev/null

if printf '%s\n' "$program_output" | grep -E 'INTERP|DYNAMIC|TLS|RWE' >/dev/null; then
    echo "forbidden hosted, TLS, dynamic, or RWX ELF state" >&2
    exit 1
fi

for symbol in _start adainit adafinal _ada_flyology_m2 \
    flyology_m2_core_entry flyology_task_start flyology_context_switch \
    flyology_current_core flyology_rts_lock_acquire \
    flyology_rts_lock_release flyology_m2_report_pass \
    flyology_m2_wait_for_timer_request \
    flyology_m2_acknowledge_requests \
    flyology_m2_parallel_task_barrier \
    flyology_m2_arm_deferred_timer flyology_m2_consume_deferred \
    flyology_m2_report_failure __gnat_last_chance_handler \
    flyology_memory_entry_is_valid flyology_topology_identities_are_distinct \
    limine_base_revision limine_memmap_request limine_mp_request; do
    printf '%s\n' "$nm_output" | grep -E "[[:space:]]$symbol$" >/dev/null
done

test -z "$(scripts/toolchain.sh exec "$architecture" "$target-nm" -u "$elf")"

case "$architecture" in
    x86_64) frame_symbols='interrupt_frames xsave_areas tss_records exception_stacks idt_transition_vector m2_idt_table' ;;
    aarch64) frame_symbols='reschedule_irq exception_stacks' ;;
esac
for symbol in $frame_symbols; do
    printf '%s\n' "$nm_output" | grep -E "[[:space:]]$symbol$" >/dev/null
done

if test "$architecture" = x86_64; then
    scripts/toolchain.sh exec "$architecture" "$target-strings" "$elf" | \
        grep -F ':IDT_TRANSITION:PASS' >/dev/null
fi

for marker in 'FLYOLOGY:M2:CORE:' ':SUBSTRATE:PASS' \
    ':INTERRUPT_FRAME:PASS' ':REQUEST_EPOCH:PASS' ':PARALLEL:PASS' \
    ':DEFERRED_REQUEST:PASS' \
    ":$reschedule:PASS" ':TIMER:PASS' 'FLYOLOGY:M2:PASS'; do
    scripts/toolchain.sh exec "$architecture" "$target-strings" "$elf" | \
        grep -F "$marker" >/dev/null
done

echo "FLYOLOGY:M2:INSPECT:PASS:$architecture"
