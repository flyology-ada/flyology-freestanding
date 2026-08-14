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
    ada__real_time__clock ada__real_time__delays__delay_until \
    system__tasking__protected_objects__lock \
    system__tasking__protected_objects__unlock \
    system__tasking__protected_objects__entries__initialize_protection_entries \
    system__tasking__protected_objects__entries__lock_entries \
    system__tasking__protected_objects__operations__protected_entry_call \
    system__tasking__protected_objects__operations__service_entries \
    system__tasking__protected_objects__operations__complete_entry_body \
    system__tasking__protected_objects__operations__exceptional_complete_entry_body \
    system__tasking__protected_objects__entries__finalize__2 \
    system__finalization_primitives__attach_object_to_node \
    system__finalization_primitives__finalize_object \
    system__tasking__rendezvous__call_simple \
    system__tasking__rendezvous__accept_call \
    system__tasking__rendezvous__complete_rendezvous \
    system__tasking__rendezvous__exceptional_complete_rendezvous \
    system__tasking__rendezvous__task_entry_call \
    system__tasking__rendezvous__timed_task_entry_call \
    system__tasking__rendezvous__selective_wait \
    ada__dynamic_priorities__set_priority \
    ada__dynamic_priorities__get_priority \
    system__tasking__stages__activate_tasks \
    system__tasking__stages__complete_activation \
    system__tasking__stages__complete_task \
    system__tasking__stages__expunge_unactivated_tasks \
    system__tasking__stages__free_task \
    system__tasking__stages__abort_tasks flyology_raise_abort \
    flyology_raise_terminate \
    ada__task_identification__current_task \
    ada__task_identification__is_callable \
    ada__task_identification__is_terminated \
    flyology__task_core__task_stacks \
    flyology__task_core__arm_wait_locked \
    flyology__task_core__resolve_exact_locked \
    flyology__task_core__install_retirement_hook \
    flyology__task_core__cancel_dormant_locked \
    flyology__task_core__begin_retirement_locked \
    flyology__task_core__finish_retirement_locked \
    flyology__priority_queue_model__select_next \
    flyology__wait_arbitration_model__resolve \
    flyology__exceptional_completion_model__complete \
    flyology__exceptional_completion_model__consume \
    flyology__dispatcher_model__try_transition \
    flyology__dispatcher_model__next_incarnation \
    flyology__placement_model__place \
    flyology__termination_model__can_select \
    flyology__termination_model__select_termination \
    __gnat_personality_v0 \
    __gnat_begin_handler_v1 __gnat_end_handler_v1 \
    system__soft_links__save_library_occurrence \
    flyology_current_exception flyology_current_exception_is_abort \
    flyology_exception_identity flyology_raise_exception_identity \
    flyology_task_root_invoke __eh_frame_start __eh_frame_end \
    __gnat_malloc __gnat_free \
    __gnat_all_others_value _Unwind_Resume \
    __gnat_last_chance_handler; do
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
    'FLYOLOGY:M4:RECLAMATION:PASS' \
    'FLYOLOGY:M3:NESTED_MASTER:PASS' 'FLYOLOGY:M3:TASK_STACKS:PASS' \
    'FLYOLOGY:M4:DELAYS:PASS' \
    'FLYOLOGY:M4:ABSOLUTE_DELAY:PASS' \
    'FLYOLOGY:M4:PROTECTED:PASS' \
    'FLYOLOGY:M4:FINALIZATION:PASS' \
    'FLYOLOGY:M4:RENDEZVOUS:PASS' \
    'FLYOLOGY:M4:EXCEPTIONAL_SYNC:PASS' \
    'FLYOLOGY:M4:UNACTIVATED_CLEANUP:PASS' \
    'FLYOLOGY:M4:ALLOCATOR_TARGET:PASS' \
    'FLYOLOGY:M4:DYNAMIC_PRIORITY:PASS' \
    'FLYOLOGY:M4:CONDITIONAL_ENTRY:PASS' \
    'FLYOLOGY:M4:TIMED_ENTRY:PASS' \
    'FLYOLOGY:M4:DYNAMIC_TASK:PASS' \
    'FLYOLOGY:M4:FREE_TASK:PASS' \
    'FLYOLOGY:M4:FREE_TASK_WAIT:PASS' \
    'FLYOLOGY:M4:FREE_TASK_ABORT_RACE:PASS' \
    'FLYOLOGY:M4:SELECTIVE_WAIT:PASS' \
    'FLYOLOGY:M4:TERMINATE_ALTERNATIVE:PASS' \
    'FLYOLOGY:M4:ABORT:PASS' \
    'FLYOLOGY:M4:ABORT_RENDEZVOUS:PASS' \
    'FLYOLOGY:M4:ABORT_TIMEOUT:PASS' \
    'FLYOLOGY:M4:ABORT_ACCEPTED:PASS' \
    'FLYOLOGY:M3:ORDINARY_TASKS:PASS' \
    'FLYOLOGY:M3:BOOT_SUBSTRATE:PASS'; do
    scripts/toolchain.sh exec "$architecture" "$target-strings" "$elf" | \
        grep -F "$marker" >/dev/null
done

echo "FLYOLOGY:M3:INSPECT:PASS:$architecture"
