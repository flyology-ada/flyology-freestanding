#!/bin/sh
set -eu

test "$#" -eq 1 || {
    echo "usage: $0 x86_64|aarch64" >&2
    exit 64
}

architecture=$1
case "$architecture" in
    x86_64) target=x86_64-elf; machine='Advanced Micro Devices X86-64' ;;
    aarch64) target=aarch64-elf; machine='AArch64' ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

elf="build/m3/$architecture/flyology-m3.elf"
test -f "$elf" || { echo "missing M3 ELF: $elf" >&2; exit 66; }

readelf_output=$(scripts/toolchain.sh exec "$architecture" \
    "$target-readelf" -h -l -S -r "$elf")
program_output=$(scripts/toolchain.sh exec "$architecture" \
    "$target-readelf" -l "$elf")
nm_output=$(scripts/toolchain.sh exec "$architecture" "$target-nm" -n "$elf")

printf '%s\n' "$readelf_output" | grep -F \
    'Class:                             ELF64' >/dev/null
printf '%s\n' "$readelf_output" | grep -F \
    'Type:                              EXEC (Executable file)' >/dev/null
printf '%s\n' "$readelf_output" | grep -F \
    "Machine:                           $machine" >/dev/null
printf '%s\n' "$readelf_output" | grep -F \
    'Entry point address:               0xffffffff80000000' >/dev/null
printf '%s\n' "$readelf_output" | grep -F \
    'There are no relocations in this file.' >/dev/null

if printf '%s\n' "$program_output" | grep -E 'INTERP|DYNAMIC|TLS|RWE' >/dev/null; then
    echo "forbidden hosted, TLS, dynamic, or RWX M3 ELF state" >&2
    exit 1
fi

for symbol in _start adainit adafinal _ada_flyology_m3 \
    flyology_task_start flyology_dispatcher_start flyology_context_switch \
    flyology_m3_prepare_environment flyology_m3_prepare_ap \
    flyology_m3_environment_complete flyology_m3_kick_core \
    flyology_m3_parallel_barrier system__tasking__stages__create_task \
    flyology_m4_read_clock flyology_m4_clock_frequency \
    flyology_m4_program_timer flyology_m4_cancel_timer \
    system__tasking__protected_objects__lock \
    system__tasking__protected_objects__unlock \
    system__tasking__stages__activate_tasks \
    system__tasking__stages__complete_activation \
    system__tasking__stages__complete_task \
    ada__task_identification__current_task \
    ada__task_identification__is_callable \
    ada__task_identification__is_terminated \
    flyology__task_core__task_stacks \
    flyology__task_core__arm_wait_locked \
    flyology__task_core__resolve_exact_locked \
    flyology__priority_queue_model__select_next \
    flyology__wait_arbitration_model__resolve \
    flyology__dispatcher_model__try_transition \
    flyology__placement_model__place __gnat_personality_v0 \
    _Unwind_Resume __gnat_last_chance_handler; do
    printf '%s\n' "$nm_output" | grep -E "[[:space:]]$symbol$" >/dev/null
done

test -z "$(scripts/toolchain.sh exec "$architecture" "$target-nm" -u "$elf")"
if printf '%s\n' "$nm_output" | grep -Ei '[[:space:]]([^[:space:]]*(spawn|fiber)|__clear_cache)$' >/dev/null; then
    echo "forbidden public task dialect, fiber, or cache-trampoline symbol" >&2
    exit 1
fi

for marker in 'FLYOLOGY:ADA:ELABORATION:PASS' \
    'FLYOLOGY:ADA:MAIN:PASS' 'FLYOLOGY:M3:SPECIFIC_CPU:PASS' \
    'FLYOLOGY:M3:AUTO_MASTER:PASS' 'FLYOLOGY:M3:AUTO_PARALLEL:PASS' \
    'FLYOLOGY:M3:NESTED_MASTER:PASS' 'FLYOLOGY:M3:TASK_STACKS:PASS' \
    'FLYOLOGY:M4:DELAYS:PASS' \
    'FLYOLOGY:M4:PROTECTED:PASS' \
    'FLYOLOGY:M3:ORDINARY_TASKS:PASS' \
    'FLYOLOGY:M3:BOOT_SUBSTRATE:PASS'; do
    scripts/toolchain.sh exec "$architecture" "$target-strings" "$elf" | \
        grep -F "$marker" >/dev/null
done

echo "FLYOLOGY:M3:INSPECT:PASS:$architecture"
