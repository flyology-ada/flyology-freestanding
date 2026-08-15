#!/bin/sh
set -eu

test "$#" -eq 2 || {
    echo "usage: $0 x86_64|aarch64 tasking|preemptive-fifo|preemptive-round-robin|domains" >&2
    exit 64
}

architecture=$1
profile=$2
case "$architecture" in
    x86_64) target=x86_64-elf; machine='Advanced Micro Devices X86-64' ;;
    aarch64) target=aarch64-elf; machine='AArch64' ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac
case "$profile" in
    tasking|preemptive-fifo|preemptive-round-robin|domains) ;;
    *) echo "unsupported image profile: $profile" >&2; exit 64 ;;
esac

output_root=${FLYOLOGY_IMAGE_OUTPUT_ROOT:-build/image}
elf="$output_root/$architecture/flyology.elf"
binder="$output_root/$architecture/b~flyology_conformance.adb"
test -f "$elf" || { echo "missing image ELF: $elf" >&2; exit 66; }
test -f "$binder" || { echo "missing image binder: $binder" >&2; exit 66; }

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
    echo "forbidden hosted, TLS, dynamic, or RWX image ELF state" >&2
    exit 1
fi

if test "$profile" != domains; then
for symbol in _start adainit adafinal _ada_flyology_conformance \
    flyology_task_start flyology_dispatcher_start flyology_context_switch \
    flyology_kernel_prepare_environment flyology_kernel_prepare_ap \
    flyology_kernel_environment_complete flyology_platform_kick_core \
    flyology_conformance_parallel_barrier system__tasking__stages__create_task \
    flyology_platform_read_clock flyology_platform_clock_frequency \
    flyology_platform_program_timer flyology_platform_cancel_timer \
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
    flyology__rts__current_active_priority \
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
    flyology__kernel__task_stacks \
    flyology__kernel__arm_wait_locked \
    flyology__kernel__resolve_exact_locked \
    flyology__kernel__install_retirement_hook \
    flyology__kernel__cancel_dormant_locked \
    flyology__kernel__begin_retirement_locked \
    flyology__kernel__finish_retirement_locked \
    flyology__priority_queue_model__select_next \
    flyology__wait_arbitration_model__resolve \
    flyology__exceptional_completion_model__complete \
    flyology__exceptional_completion_model__consume \
    flyology__dispatcher_model__try_transition \
    flyology__dispatcher_model__next_incarnation \
    flyology__domain_model__place \
    flyology__abort_closure_model__close \
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
fi

test -z "$(scripts/toolchain.sh exec "$architecture" "$target-nm" -u "$elf")"
if printf '%s\n' "$nm_output" | grep -Ei '[[:space:]]([^[:space:]]*(spawn|fiber)|__clear_cache)$' >/dev/null; then
    echo "forbidden public task dialect, fiber, or cache-trampoline symbol" >&2
    exit 1
fi

if test "$profile" != domains; then
for marker in 'FLYOLOGY:ADA:ELABORATION:PASS' \
    'FLYOLOGY:ADA:MAIN:PASS' 'FLYOLOGY:TASKING:SPECIFIC_CPU:PASS' \
    'FLYOLOGY:TASKING:AUTO_MASTER:PASS' 'FLYOLOGY:TASKING:AUTO_PARALLEL:PASS' \
    'FLYOLOGY:RTS:RECLAMATION:PASS' \
    'FLYOLOGY:TASKING:NESTED_MASTER:PASS' 'FLYOLOGY:TASKING:TASK_STACKS:PASS' \
    'FLYOLOGY:RTS:DELAYS:PASS' \
    'FLYOLOGY:RTS:ABSOLUTE_DELAY:PASS' \
    'FLYOLOGY:RTS:PROTECTED:PASS' \
    'FLYOLOGY:RTS:FINALIZATION:PASS' \
    'FLYOLOGY:RTS:RENDEZVOUS:PASS' \
    'FLYOLOGY:RTS:EXCEPTIONAL_SYNC:PASS' \
    'FLYOLOGY:RTS:EXCEPTIONAL_PROTECTED_IMMEDIATE:PASS' \
    'FLYOLOGY:RTS:EXCEPTIONAL_PROTECTED_QUEUED:PASS' \
    'FLYOLOGY:RTS:EXCEPTION_ABORT_PROTECTED:PASS' \
    'FLYOLOGY:RTS:EXCEPTIONAL_RENDEZVOUS:PASS' \
    'FLYOLOGY:RTS:EXCEPTION_ABORT:PASS' \
    'FLYOLOGY:RTS:UNACTIVATED_CLEANUP:PASS' \
    'FLYOLOGY:RTS:ALLOCATOR_TARGET:PASS' \
    'FLYOLOGY:RTS:DYNAMIC_PRIORITY:PASS' \
    'FLYOLOGY:RTS:CEILING:PASS' \
    'FLYOLOGY:RTS:CONDITIONAL_ENTRY:PASS' \
    'FLYOLOGY:RTS:TIMED_ENTRY:PASS' \
    'FLYOLOGY:RTS:DYNAMIC_TASK:PASS' \
    'FLYOLOGY:RTS:FREE_TASK:PASS' \
    'FLYOLOGY:RTS:FREE_TASK_WAIT:PASS' \
    'FLYOLOGY:RTS:FREE_TASK_ABORT_RACE:PASS' \
    'FLYOLOGY:RTS:SELECTIVE_WAIT:PASS' \
    'FLYOLOGY:RTS:TERMINATE_ALTERNATIVE:PASS' \
    'FLYOLOGY:RTS:ABORT:PASS' \
    'FLYOLOGY:RTS:MULTI_ABORT:PASS' \
    'FLYOLOGY:RTS:DEPENDENT_ABORT:PASS' \
    'FLYOLOGY:RTS:ABORT_RENDEZVOUS:PASS' \
    'FLYOLOGY:RTS:ABORT_TIMEOUT:PASS' \
    'FLYOLOGY:RTS:ABORT_ACCEPTED:PASS' \
    'FLYOLOGY:RTS:ABORT_PROTECTED:PASS' \
    'FLYOLOGY:RTS:COLLISION_STRESS:PASS' \
    'FLYOLOGY:TASKING:ORDINARY_TASKS:PASS' \
    'FLYOLOGY:TASKING:BOOT_SUBSTRATE:PASS'; do
    scripts/toolchain.sh exec "$architecture" "$target-strings" "$elf" | \
        grep -F "$marker" >/dev/null
done
fi

strings_output=$(scripts/toolchain.sh exec \
    "$architecture" "$target-strings" "$elf")

case "$profile" in
    tasking) ;;
    preemptive-fifo|preemptive-round-robin|domains)
        for symbol in flyology_kernel_interrupt_dispatch \
            flyology_conformance_preemption_canary \
            flyology_platform_retry_interrupt flyology_platform_retry_count \
            flyology_rts_lock_try_acquire \
            flyology_context_switch_to_task flyology_context_switch_to_full \
            flyology__platform__capture_full_context \
            flyology__preemption_model__configuration_is_valid \
            flyology__preemption_model__quantum_ticks \
            flyology__preemption_model__account \
            flyology__preemption_model__decide \
            __gl_time_slice_val __gl_task_dispatching_policy; do
            printf '%s\n' "$nm_output" | \
                grep -E "[[:space:]]$symbol$" >/dev/null
        done
        for marker in FIFO_PREEMPTION ROUND_ROBIN REMOTE_PREEMPTION \
            ALL_CORE_PREEMPTION FIFO_NO_ROTATION PRIORITY_REQUEUE \
            NONBLOCKING_INGRESS; do
            printf '%s\n' "$strings_output" | \
                grep -F "FLYOLOGY:PREEMPTION:$marker:PASS" >/dev/null
        done
        ;;
esac

case "$profile" in
    preemptive-fifo|domains)
        grep -F "Time_Slice_Value := 0;" "$binder" >/dev/null
        grep -F "Task_Dispatching_Policy := 'F';" "$binder" >/dev/null
        ;;
    preemptive-round-robin)
        grep -F "Time_Slice_Value := 10000;" "$binder" >/dev/null
        grep -F "Task_Dispatching_Policy := 'R';" "$binder" >/dev/null
        ;;
    tasking) ;;
esac

if test "$profile" = domains; then
    for symbol in _start adainit adafinal _ada_flyology_conformance \
        flyology_task_start flyology_dispatcher_start \
        flyology_context_switch flyology_kernel_prepare_environment \
        flyology_kernel_prepare_ap flyology_kernel_environment_complete \
        system__tasking__stages__create_task \
        system__tasking__stages__activate_tasks \
        system__multiprocessors__number_of_cpus \
        system__multiprocessors__dispatching_domains__create \
        system__multiprocessors__dispatching_domains__get_cpu_set \
        system__multiprocessors__dispatching_domains__get_dispatching_domain \
        system__multiprocessors__dispatching_domains__get_cpu \
        __gnat_freeze_dispatching_domains \
        system__secondary_stack__ss_mark system__secondary_stack__ss_release \
        system__secondary_stack__ss_allocate \
        flyology__rts__register_domain_alias flyology__rts__create_domain \
        flyology__kernel__try_create_domain_locked \
        flyology__kernel__activate_locked \
        flyology__domain_model__valid flyology__domain_model__try_create \
        flyology__domain_model__place flyology__domain_model__try_admit; do
        printf '%s\n' "$nm_output" | \
            grep -E "[[:space:]]$symbol$" >/dev/null
    done
    for marker in DOMAIN_LAYOUT STANDARD_QUERIES DOMAIN_INHERITANCE \
        HETEROGENEOUS_POLICY ALL_CORE_PREEMPTION; do
        printf '%s\n' "$strings_output" | \
            grep -F "FLYOLOGY:DOMAINS:$marker:PASS" >/dev/null
    done
    grep -F '__gnat_freeze_dispatching_domains' "$binder" >/dev/null
fi

echo "FLYOLOGY:IMAGE:INSPECT:PASS:$architecture:$profile"
