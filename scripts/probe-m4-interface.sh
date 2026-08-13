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
    rm -f "$output/absolute_delay_probe.ali" \
          "$output/absolute_delay_probe.o" \
          "$output/absolute_delay_probe.expanded" \
          "$output/absolute_delay_probe.undefined"
    rm -f "$output/selective_wait_probe.ali" \
          "$output/selective_wait_probe.o" \
          "$output/selective_wait_probe.expanded" \
          "$output/selective_wait_probe.undefined"

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
        -I"$repository/runtime/bootstrap" -I"$repository/runtime/core" \
        -I"$repository/runtime/m3" -gnat2022 -gnatG -gnatf \
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

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/m4/simple_rendezvous_probe.adb" \
        -o simple_rendezvous_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/runtime/core" \
        -I"$repository/runtime/m3" -gnat2022 -gnatG -gnatf \
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
        -I"$repository/runtime/bootstrap" -I"$repository/runtime/core" \
        -I"$repository/runtime/m3" -gnat2022 -gnatG -gnatf \
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
        -I"$repository/runtime/bootstrap" -I"$repository/runtime/core" \
        -I"$repository/runtime/m3" -gnat2022 -gnatG -gnatf \
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
        -I"$repository/runtime/bootstrap" -I"$repository/runtime/core" \
        -I"$repository/runtime/m3" -gnat2022 -gnatG -gnatf \
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
        -I"$repository/runtime/bootstrap" -I"$repository/runtime/core" \
        -I"$repository/runtime/m3" -gnat2022 -gnatG -gnatf \
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
        "$repository/probes/m4/absolute_delay_probe.adb" \
        -o absolute_delay_probe.o -nostdinc \
        -I"$repository/runtime/bootstrap" -I"$repository/runtime/core" \
        -I"$repository/runtime/m3" -gnat2022 -gnatG -gnatf \
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
        -I"$repository/runtime/bootstrap" -I"$repository/runtime/core" \
        -I"$repository/runtime/m3" -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/runtime/bootstrap/m1.adc" \
        >"$output/selective_wait_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u selective_wait_probe.o \
        >"$output/selective_wait_probe.undefined"
    grep -F ' system__tasking__rendezvous__selective_wait' \
        "$output/selective_wait_probe.undefined" >/dev/null
    grep -F 'system__tasking__terminate_mode' \
        "$output/selective_wait_probe.expanded" >/dev/null
    echo "FLYOLOGY:M4:PROBE:PASS:$architecture"
done

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
echo 'FLYOLOGY:M4:PROBE:PASS'
