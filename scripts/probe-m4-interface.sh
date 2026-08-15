#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_root="$repository/build/probes/m4"
interface_root="$repository/probes/m4/interfaces"
mkdir -p "$output_root"

for architecture in x86_64 aarch64; do
    case "$architecture" in
        x86_64) target=x86_64-elf ;;
        aarch64) target=aarch64-elf ;;
    esac
    output="$output_root/$architecture"
    mkdir -p "$output"
    rm -f "$output/exception_probe.ali" "$output/exception_probe.o" \
          "$output/exception_probe.expanded" \
          "$output/exception_probe.undefined" \
          "$output/exception_probe.sections"
    rm -f "$output/base_protected_probe.ali" \
          "$output/base_protected_probe.o" \
          "$output/base_protected_probe.expanded" \
          "$output/base_protected_probe.undefined"
    rm -f "$output/protected_probe.ali" "$output/protected_probe.o" \
          "$output/protected_probe.expanded" \
          "$output/protected_probe.undefined" \
          "$output/protected_conditional_probe.ali" \
          "$output/protected_conditional_probe.o" \
          "$output/protected_conditional_probe.expanded" \
          "$output/protected_conditional_probe.undefined" \
          "$output/protected_timed_probe.ali" \
          "$output/protected_timed_probe.o" \
          "$output/protected_timed_probe.expanded" \
          "$output/protected_timed_probe.undefined"
    rm -f "$output/simple_rendezvous_probe.ali" \
          "$output/simple_rendezvous_probe.o" \
          "$output/simple_rendezvous_probe.expanded" \
          "$output/simple_rendezvous_probe.undefined"
    rm -f "$output/dynamic_priority_probe.ali" \
          "$output/dynamic_priority_probe.o" \
          "$output/dynamic_priority_probe.expanded" \
          "$output/dynamic_priority_probe.undefined"
    rm -f "$output/conditional_rendezvous_probe.ali" \
          "$output/conditional_rendezvous_probe.o" \
          "$output/conditional_rendezvous_probe.expanded" \
          "$output/conditional_rendezvous_probe.undefined"
    rm -f "$output/timed_rendezvous_probe.ali" \
          "$output/timed_rendezvous_probe.o" \
          "$output/timed_rendezvous_probe.expanded" \
          "$output/timed_rendezvous_probe.undefined"
    rm -f "$output/dynamic_task_probe.ali" \
          "$output/dynamic_task_probe.o" \
          "$output/dynamic_task_probe.expanded" \
          "$output/dynamic_task_probe.undefined"
    rm -f "$output/activation_failure_probe.ali" \
          "$output/activation_failure_probe.o" \
          "$output/activation_failure_probe.expanded" \
          "$output/activation_failure_probe.undefined"
    rm -f "$output/absolute_delay_probe.ali" \
          "$output/absolute_delay_probe.o" \
          "$output/absolute_delay_probe.expanded" \
          "$output/absolute_delay_probe.undefined"
    rm -f "$output/selective_wait_probe.ali" \
          "$output/selective_wait_probe.o" \
          "$output/selective_wait_probe.expanded" \
          "$output/selective_wait_probe.undefined"
    rm -f "$output/abort_probe.ali" "$output/abort_probe.o" \
          "$output/abort_probe.expanded" "$output/abort_probe.undefined" \
          "$output/abort_dynamic_probe.ali" \
          "$output/abort_dynamic_probe.o" \
          "$output/abort_dynamic_probe.expanded" \
          "$output/abort_dynamic_probe.undefined" \
          "$output/a-uncdea.ali" "$output/a-uncdea.o" \
          "$output/task_root_probe.ali" "$output/task_root_probe.o" \
          "$output/task_root_probe.expanded" \
          "$output/task_root_probe.undefined"

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c "$repository/probes/m4/exception_probe.adb" \
        -o exception_probe.o -nostdinc -I"$interface_root" \
        -gnat2022 -gnatG -gnatf \
        >"$output/exception_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u exception_probe.o \
        >"$output/exception_probe.undefined"
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-objdump" -sj .gcc_except_table exception_probe.o \
        >"$output/exception_probe.sections"

    for symbol in _Unwind_Resume __gnat_begin_handler_v1 \
        __gnat_end_handler_v1 __gnat_personality_v0 \
        __gnat_rcheck_PE_Explicit_Raise program_error; do
        grep -F " $symbol" "$output/exception_probe.undefined" >/dev/null
    done
    test "$(wc -l <"$output/exception_probe.undefined" | tr -d ' ')" -eq 6
    grep -F 'when program_error =>' "$output/exception_probe.expanded" \
        >/dev/null
    grep -F 'Contents of section .gcc_except_table' \
        "$output/exception_probe.sections" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c "$repository/probes/m4/base_protected_probe.adb" \
        -o base_protected_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/base_protected_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u base_protected_probe.o \
        >"$output/base_protected_probe.undefined"
    for symbol in system__tasking__protected_objects__initialize_protection \
        system__tasking__protected_objects__lock \
        system__tasking__protected_objects__lock_read_only \
        system__tasking__protected_objects__unlock \
        system__tasking__protected_objects__finalize_protection \
        system__finalization_primitives__attach_object_to_node \
        system__finalization_primitives__finalize_object; do
        grep -F " $symbol" "$output/base_protected_probe.undefined" \
            >/dev/null
    done
    grep -F 'system__tasking__protected_objects__lock (' \
        "$output/base_protected_probe.expanded" >/dev/null
    grep -F 'system__tasking__protected_objects__lock_read_only (' \
        "$output/base_protected_probe.expanded" >/dev/null
    grep -F 'with priority => 8;' \
        "$output/base_protected_probe.expanded" >/dev/null
    grep -F 'system__any_priority := 8;' \
        "$output/base_protected_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c "$repository/probes/m4/protected_probe.adb" \
        -o protected_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/m4/product.adc" \
        >"$output/protected_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u protected_probe.o \
        >"$output/protected_probe.undefined"
    for symbol in \
        system__tasking__protected_objects__entries__initialize_protection_entries \
        system__tasking__protected_objects__entries__lock_entries \
        system__tasking__protected_objects__entries__unlock_entries \
        system__tasking__protected_objects__operations__communication_blockIP \
        system__tasking__protected_objects__operations__complete_entry_body \
        system__tasking__protected_objects__operations__exceptional_complete_entry_body \
        system__tasking__protected_objects__operations__protected_entry_call \
        system__tasking__protected_objects__operations__service_entries \
        system__tasking__protected_objects__entries__finalize__2 \
        system__finalization_primitives__attach_object_to_node \
        system__finalization_primitives__finalize_object; do
        grep -F " $symbol" "$output/protected_probe.undefined" >/dev/null
    done
    grep -F 'protected_entry_body_array' \
        "$output/protected_probe.expanded" >/dev/null
    grep -F 'system__tasking__protected_objects__operations__service_entries' \
        "$output/protected_probe.expanded" >/dev/null
    grep -F 'when all others =>' \
        "$output/protected_probe.expanded" >/dev/null
    grep -F 'system__tasking__protected_objects__operations__exceptional_complete_entry_body' \
        "$output/protected_probe.expanded" >/dev/null
    grep -F 'system__soft_links__get_gnat_exception' \
        "$output/protected_probe.expanded" >/dev/null
    grep -F 'procedure protected_probe__gateTVFD' \
        "$output/protected_probe.expanded" >/dev/null
    grep -F 'protected_probe__gateTVFD' \
        "$output/protected_probe.expanded" | \
        grep -F 'unrestricted_access' >/dev/null
    if grep -F 'any id' "$output/protected_probe.expanded" >/dev/null; then
        echo "anonymous protected finalizer callback: $architecture" >&2
        exit 1
    fi

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/protected_conditional_probe.adb" \
        -o protected_conditional_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/m4/product.adc" \
        >"$output/protected_conditional_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u protected_conditional_probe.o \
        >"$output/protected_conditional_probe.undefined"
    for symbol in \
        system__tasking__protected_objects__operations__cancelled \
        system__tasking__protected_objects__operations__protected_count \
        system__tasking__protected_objects__operations__protected_entry_call; do
        grep -F " $symbol" "$output/protected_conditional_probe.undefined" \
            >/dev/null
    done
    grep -F 'system__tasking__conditional_call' \
        "$output/protected_conditional_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/protected_timed_probe.adb" \
        -o protected_timed_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/m4/product.adc" \
        >"$output/protected_timed_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u protected_timed_probe.o \
        >"$output/protected_timed_probe.undefined"
    grep -F \
        ' system__tasking__protected_objects__operations__timed_protected_entry_call' \
        "$output/protected_timed_probe.undefined" >/dev/null
    grep -F 'timed_protected_entry_call' \
        "$output/protected_timed_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/simple_rendezvous_probe.adb" \
        -o simple_rendezvous_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/simple_rendezvous_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u simple_rendezvous_probe.o \
        >"$output/simple_rendezvous_probe.undefined"
    for symbol in __gnat_all_others_value __gnat_begin_handler_v1 \
        __gnat_end_handler_v1 __gnat_personality_v0 \
        system__soft_links__get_gnat_exception \
        system__tasking__rendezvous__accept_call \
        system__tasking__rendezvous__call_simple \
        system__tasking__rendezvous__complete_rendezvous \
        system__tasking__rendezvous__exceptional_complete_rendezvous; do
        grep -F " $symbol" "$output/simple_rendezvous_probe.undefined" \
            >/dev/null
    done
    grep -F 'system__tasking__rendezvous__accept_call (1,' \
        "$output/simple_rendezvous_probe.expanded" >/dev/null
    grep -F 'system__tasking__rendezvous__call_simple (' \
        "$output/simple_rendezvous_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/dynamic_priority_probe.adb" \
        -o dynamic_priority_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/dynamic_priority_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u dynamic_priority_probe.o \
        >"$output/dynamic_priority_probe.undefined"
    for symbol in ada__dynamic_priorities__get_priority \
        ada__dynamic_priorities__set_priority \
        ada__task_identification__current_task; do
        grep -F " $symbol" "$output/dynamic_priority_probe.undefined" \
            >/dev/null
    done
    grep -F 'ada__dynamic_priorities__set_priority (' \
        "$output/dynamic_priority_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/conditional_rendezvous_probe.adb" \
        -o conditional_rendezvous_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/conditional_rendezvous_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u conditional_rendezvous_probe.o \
        >"$output/conditional_rendezvous_probe.undefined"
    grep -F ' system__tasking__rendezvous__task_entry_call' \
        "$output/conditional_rendezvous_probe.undefined" >/dev/null
    grep -F 'system__tasking__conditional_call' \
        "$output/conditional_rendezvous_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/timed_rendezvous_probe.adb" \
        -o timed_rendezvous_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/timed_rendezvous_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u timed_rendezvous_probe.o \
        >"$output/timed_rendezvous_probe.undefined"
    grep -F ' system__tasking__rendezvous__timed_task_entry_call' \
        "$output/timed_rendezvous_probe.undefined" >/dev/null
    grep -F 'system__tasking__rendezvous__timed_task_entry_call (' \
        "$output/timed_rendezvous_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/dynamic_task_probe.adb" \
        -o dynamic_task_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/dynamic_task_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u dynamic_task_probe.o \
        >"$output/dynamic_task_probe.undefined"
    for symbol in __gnat_malloc \
        system__tasking__stages__expunge_unactivated_tasks \
        system__tasking__stages__create_task \
        system__tasking__stages__activate_tasks \
        system__tasking__stages__complete_task; do
        grep -F " $symbol" "$output/dynamic_task_probe.undefined" >/dev/null
    done
    grep -F 'system__tasking__stages__expunge_unactivated_tasks (' \
        "$output/dynamic_task_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/activation_failure_probe.adb" \
        -o activation_failure_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/activation_failure_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u activation_failure_probe.o \
        >"$output/activation_failure_probe.undefined"
    for symbol in system__tasking__stages__create_task \
        system__tasking__stages__activate_tasks \
        system__tasking__stages__complete_activation \
        system__tasking__stages__complete_task \
        system__soft_links__enter_master \
        system__soft_links__complete_master; do
        grep -F " $symbol" \
            "$output/activation_failure_probe.undefined" >/dev/null
    done
    fail_line=$(grep -nF 'activation_failure_probe__fail;' \
        "$output/activation_failure_probe.expanded" | head -n 1 | cut -d: -f1)
    activation_line=$(grep -nF \
        'system__tasking__stages__complete_activation;' \
        "$output/activation_failure_probe.expanded" | head -n 1 | cut -d: -f1)
    test -n "$fail_line" && test -n "$activation_line"
    test "$fail_line" -lt "$activation_line"
    grep -F 'system__tasking__stages__complete_task;' \
        "$output/activation_failure_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/absolute_delay_probe.adb" \
        -o absolute_delay_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/absolute_delay_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u absolute_delay_probe.o \
        >"$output/absolute_delay_probe.undefined"
    for symbol in ada__real_time__clock \
        ada__real_time__milliseconds \
        ada__real_time__delays__delay_until; do
        grep -F " $symbol" "$output/absolute_delay_probe.undefined" >/dev/null
    done
    grep -F 'ada__real_time__delays__delay_until (deadline)' \
        "$output/absolute_delay_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/selective_wait_probe.adb" \
        -o selective_wait_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/selective_wait_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u selective_wait_probe.o \
        >"$output/selective_wait_probe.undefined"
    grep -F ' system__tasking__rendezvous__selective_wait' \
        "$output/selective_wait_probe.undefined" >/dev/null
    grep -F 'system__tasking__terminate_mode' \
        "$output/selective_wait_probe.expanded" >/dev/null
    grep -F 'when system__tasking__no_rendezvous =>' \
        "$output/selective_wait_probe.expanded" >/dev/null
    grep -F 'null_body => true' \
        "$output/selective_wait_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c "$repository/probes/m4/abort_probe.adb" \
        -o abort_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/abort_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u abort_probe.o >"$output/abort_probe.undefined"
    grep -F ' system__tasking__stages__abort_tasks' \
        "$output/abort_probe.undefined" >/dev/null
    grep -F 'system__tasking__stages__abort_tasks (' \
        "$output/abort_probe.expanded" >/dev/null
    grep -F "system__tasking__task_list'((" \
        "$output/abort_probe.expanded" >/dev/null
    grep -F 'abort_probe__firstTKV!(first)._task_id' \
        "$output/abort_probe.expanded" >/dev/null
    grep -F 'abort_probe__secondTKV!(' \
        "$output/abort_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/abort_dynamic_probe.adb" \
        -o abort_dynamic_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/m4/product.adc" \
        >"$output/abort_dynamic_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u abort_dynamic_probe.o \
        >"$output/abort_dynamic_probe.undefined"
    for symbol in __gnat_free system__tasking__stages__free_task \
        system__tasking__stages__abort_tasks; do
        grep -F " $symbol" "$output/abort_dynamic_probe.undefined" \
            >/dev/null
    done
    abort_line=$(grep -nF 'system__tasking__stages__abort_tasks (' \
        "$output/abort_dynamic_probe.expanded" | tail -n 1 | cut -d: -f1)
    free_line=$(grep -nF 'system__tasking__stages__free_task (' \
        "$output/abort_dynamic_probe.expanded" | tail -n 1 | cut -d: -f1)
    raw_free_line=$(grep -nF 'free item;' \
        "$output/abort_dynamic_probe.expanded" | tail -n 1 | cut -d: -f1)
    null_line=$(grep -nF 'item := null;' \
        "$output/abort_dynamic_probe.expanded" | tail -n 1 | cut -d: -f1)
    test -n "$abort_line" && test -n "$free_line" && \
        test -n "$raw_free_line" && test -n "$null_line"
    test "$abort_line" -lt "$free_line"
    test "$free_line" -lt "$raw_free_line"
    test "$raw_free_line" -lt "$null_line"
    grep -F 'abort_dynamic_probe__workerV!(item.all)._task_id' \
        "$output/abort_dynamic_probe.expanded" >/dev/null
    grep -E 'worker_accessM[0-9]+b : integer renames _master;' \
        "$output/abort_dynamic_probe.expanded" >/dev/null

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c "$repository/probes/m4/task_root_probe.adb" \
        -o task_root_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/src/primitives" \
        -I"$repository/src/gnarl" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/task_root_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u task_root_probe.o \
        >"$output/task_root_probe.undefined"
    for symbol in _Unwind_Resume __gnat_begin_handler_v1 \
        __gnat_end_handler_v1 __gnat_others_value \
        __gnat_personality_v0; do
        grep -F " $symbol" "$output/task_root_probe.undefined" >/dev/null
    done
    test "$(wc -l <"$output/task_root_probe.undefined" | tr -d ' ')" -eq 5
    echo "FLYOLOGY:M4:PROBE:PASS:$architecture"
done

# The hosted GNAT 15.3 runtime is used only as black-box lowering evidence for
# the language-defined generic. The product supplies the ARM-shaped intrinsic
# declaration and its clean-room Stages facade, not a replacement generic body.
native_prefix=${FLYOLOGY_NATIVE_GNAT_PREFIX:-"$HOME/.local/share/alire/toolchains/gnat_native_15.3.1_36dc7314"}
native_compiler="$native_prefix/bin/gcc"
native_digest=fa728e60b2dc7e3dff407ab847725d8145f3301615bad70c39ef422c8e8b741d
llvm_root=${FLYOLOGY_LLVM_ROOT:-/opt/homebrew/opt/llvm/bin}
llvm_nm="$llvm_root/llvm-nm"
llvm_objdump="$llvm_root/llvm-objdump"
llvm_nm_digest=98877e5da3a0591c4abeaf1819ca81976e886ec17550b10f81b0f5569890d5b5
llvm_objdump_digest=8d34812bfab8a85918ad8502890ef1c4dca02273687e0b5e4a18cd6864ce5e78
native_output="$output_root/native"
mkdir -p "$native_output"
rm -f "$native_output/abort_dynamic_probe.ali" \
      "$native_output/abort_dynamic_probe.o" \
      "$native_output/abort_dynamic_probe.expanded" \
      "$native_output/abort_dynamic_probe.undefined" \
      "$native_output/abort_dynamic_probe.relocations"
test -x "$native_compiler"
printf '%s  %s\n' "$native_digest" "$native_compiler" | \
    shasum -a 256 -c - >/dev/null
test "$("$native_compiler" --version | sed -n '1p')" = \
    'gcc (GNAT-FSF-builds) 15.3.0'
for tool_and_digest in "$llvm_nm:$llvm_nm_digest" \
    "$llvm_objdump:$llvm_objdump_digest"; do
    tool=${tool_and_digest%:*}
    digest=${tool_and_digest#*:}
    test -x "$tool"
    printf '%s  %s\n' "$digest" "$tool" | shasum -a 256 -c - >/dev/null
done
test "$("$llvm_objdump" --version | sed -n '1p')" = \
    'Homebrew LLVM version 22.1.8'
(
    cd "$native_output"
    "$native_compiler" -c -O0 -gnat2022 -gnatG -gnatf \
        "$repository/probes/m4/abort_dynamic_probe.adb" \
        -o abort_dynamic_probe.o >abort_dynamic_probe.expanded 2>&1
    "$llvm_nm" -u abort_dynamic_probe.o >abort_dynamic_probe.undefined
    "$llvm_objdump" -dr abort_dynamic_probe.o \
        >abort_dynamic_probe.relocations
)
for symbol in ___gnat_free _system__tasking__stages__abort_tasks \
    _system__tasking__stages__free_task; do
    grep -Fx "$symbol" "$native_output/abort_dynamic_probe.undefined" \
        >/dev/null
done
native_abort_offset=$(grep '_system__tasking__stages__abort_tasks$' \
    "$native_output/abort_dynamic_probe.relocations" | \
    sed -n 's/^[[:space:]]*\([0-9a-f][0-9a-f]*\):.*/\1/p')
native_free_offset=$(grep '_system__tasking__stages__free_task$' \
    "$native_output/abort_dynamic_probe.relocations" | \
    sed -n 's/^[[:space:]]*\([0-9a-f][0-9a-f]*\):.*/\1/p')
native_raw_free_offset=$(grep '___gnat_free$' \
    "$native_output/abort_dynamic_probe.relocations" | \
    sed -n 's/^[[:space:]]*\([0-9a-f][0-9a-f]*\):.*/\1/p')
test -n "$native_abort_offset" && test -n "$native_free_offset" && \
    test -n "$native_raw_free_offset"
test "$((0x$native_abort_offset))" -lt "$((0x$native_free_offset))"
test "$((0x$native_free_offset))" -lt "$((0x$native_raw_free_offset))"
grep -F 'system__tasking__stages__free_task (' \
    "$native_output/abort_dynamic_probe.expanded" >/dev/null
grep -F 'abort_dynamic_probe__workerV!(item.all)._task_id' \
    "$native_output/abort_dynamic_probe.expanded" >/dev/null
grep -E 'worker_accessM[0-9]+b : integer renames _master;' \
    "$native_output/abort_dynamic_probe.expanded" >/dev/null
native_source_free=$(grep -nF 'free item;' \
    "$native_output/abort_dynamic_probe.expanded" | tail -n 1 | cut -d: -f1)
native_source_null=$(grep -nF 'item := null;' \
    "$native_output/abort_dynamic_probe.expanded" | tail -n 1 | cut -d: -f1)
test -n "$native_source_free" && test -n "$native_source_null"
test "$native_source_free" -lt "$native_source_null"
echo 'FLYOLOGY:M4:PROBE:PASS:native-free-task'

diff -u "$output_root/x86_64/exception_probe.undefined" \
    "$output_root/aarch64/exception_probe.undefined" >/dev/null
test "$(grep -c ' __clear_cache$' \
    "$output_root/x86_64/base_protected_probe.undefined" || true)" -eq 0
test "$(grep -c ' __clear_cache$' \
    "$output_root/aarch64/base_protected_probe.undefined")" -eq 1
grep -v ' __clear_cache$' \
    "$output_root/aarch64/base_protected_probe.undefined" \
    >"$output_root/aarch64/base_protected_probe.normalized"
diff -u "$output_root/x86_64/base_protected_probe.undefined" \
    "$output_root/aarch64/base_protected_probe.normalized" >/dev/null
test "$(grep -c ' __clear_cache$' \
    "$output_root/x86_64/protected_probe.undefined" || true)" -eq 0
test "$(grep -c ' __clear_cache$' \
    "$output_root/aarch64/protected_probe.undefined")" -eq 1
grep -v ' __clear_cache$' \
    "$output_root/aarch64/protected_probe.undefined" \
    >"$output_root/aarch64/protected_probe.normalized"
diff -u "$output_root/x86_64/protected_probe.undefined" \
    "$output_root/aarch64/protected_probe.normalized" >/dev/null
test "$(grep -c ' __clear_cache$' \
    "$output_root/x86_64/protected_conditional_probe.undefined" || true)" -eq 0
test "$(grep -c ' __clear_cache$' \
    "$output_root/aarch64/protected_conditional_probe.undefined")" -eq 1
grep -v ' __clear_cache$' \
    "$output_root/aarch64/protected_conditional_probe.undefined" \
    >"$output_root/aarch64/protected_conditional_probe.normalized"
diff -u "$output_root/x86_64/protected_conditional_probe.undefined" \
    "$output_root/aarch64/protected_conditional_probe.normalized" >/dev/null
test "$(grep -c ' __clear_cache$' \
    "$output_root/x86_64/protected_timed_probe.undefined" || true)" -eq 0
test "$(grep -c ' __clear_cache$' \
    "$output_root/aarch64/protected_timed_probe.undefined")" -eq 1
grep -v ' __clear_cache$' \
    "$output_root/aarch64/protected_timed_probe.undefined" \
    >"$output_root/aarch64/protected_timed_probe.normalized"
diff -u "$output_root/x86_64/protected_timed_probe.undefined" \
    "$output_root/aarch64/protected_timed_probe.normalized" >/dev/null
test "$(grep -c ' __clear_cache$' \
    "$output_root/x86_64/simple_rendezvous_probe.undefined" || true)" -eq 0
test "$(grep -c ' __clear_cache$' \
    "$output_root/aarch64/simple_rendezvous_probe.undefined")" -eq 1
grep -v ' __clear_cache$' \
    "$output_root/aarch64/simple_rendezvous_probe.undefined" \
    >"$output_root/aarch64/simple_rendezvous_probe.normalized"
diff -u "$output_root/x86_64/simple_rendezvous_probe.undefined" \
    "$output_root/aarch64/simple_rendezvous_probe.normalized" >/dev/null
diff -u "$output_root/x86_64/dynamic_priority_probe.undefined" \
    "$output_root/aarch64/dynamic_priority_probe.undefined" >/dev/null
test "$(grep -c ' __clear_cache$' \
    "$output_root/x86_64/conditional_rendezvous_probe.undefined" || true)" \
    -eq 0
test "$(grep -c ' __clear_cache$' \
    "$output_root/aarch64/conditional_rendezvous_probe.undefined")" -eq 1
grep -v ' __clear_cache$' \
    "$output_root/aarch64/conditional_rendezvous_probe.undefined" \
    >"$output_root/aarch64/conditional_rendezvous_probe.normalized"
diff -u "$output_root/x86_64/conditional_rendezvous_probe.undefined" \
    "$output_root/aarch64/conditional_rendezvous_probe.normalized" >/dev/null
test "$(grep -c ' __clear_cache$' \
    "$output_root/x86_64/timed_rendezvous_probe.undefined" || true)" -eq 0
test "$(grep -c ' __clear_cache$' \
    "$output_root/aarch64/timed_rendezvous_probe.undefined")" -eq 1
grep -v ' __clear_cache$' \
    "$output_root/aarch64/timed_rendezvous_probe.undefined" \
    >"$output_root/aarch64/timed_rendezvous_probe.normalized"
diff -u "$output_root/x86_64/timed_rendezvous_probe.undefined" \
    "$output_root/aarch64/timed_rendezvous_probe.normalized" >/dev/null
test "$(grep -c ' __clear_cache$' \
    "$output_root/x86_64/dynamic_task_probe.undefined" || true)" -eq 0
test "$(grep -c ' __clear_cache$' \
    "$output_root/aarch64/dynamic_task_probe.undefined")" -eq 1
grep -v ' __clear_cache$' \
    "$output_root/aarch64/dynamic_task_probe.undefined" \
    >"$output_root/aarch64/dynamic_task_probe.normalized"
diff -u "$output_root/x86_64/dynamic_task_probe.undefined" \
    "$output_root/aarch64/dynamic_task_probe.normalized" >/dev/null
diff -u "$output_root/x86_64/absolute_delay_probe.undefined" \
    "$output_root/aarch64/absolute_delay_probe.undefined" >/dev/null
test "$(grep -c ' __clear_cache$' \
    "$output_root/x86_64/selective_wait_probe.undefined" || true)" -eq 0
test "$(grep -c ' __clear_cache$' \
    "$output_root/aarch64/selective_wait_probe.undefined")" -eq 1
grep -v ' __clear_cache$' \
    "$output_root/aarch64/selective_wait_probe.undefined" \
    >"$output_root/aarch64/selective_wait_probe.normalized"
diff -u "$output_root/x86_64/selective_wait_probe.undefined" \
    "$output_root/aarch64/selective_wait_probe.normalized" >/dev/null
test "$(grep -c ' __clear_cache$' \
    "$output_root/x86_64/abort_probe.undefined" || true)" -eq 0
test "$(grep -c ' __clear_cache$' \
    "$output_root/aarch64/abort_probe.undefined")" -eq 1
grep -v ' __clear_cache$' "$output_root/aarch64/abort_probe.undefined" \
    >"$output_root/aarch64/abort_probe.normalized"
diff -u "$output_root/x86_64/abort_probe.undefined" \
    "$output_root/aarch64/abort_probe.normalized" >/dev/null
diff -u "$output_root/x86_64/task_root_probe.undefined" \
    "$output_root/aarch64/task_root_probe.undefined" >/dev/null
echo 'FLYOLOGY:M4:PROBE:PASS'
