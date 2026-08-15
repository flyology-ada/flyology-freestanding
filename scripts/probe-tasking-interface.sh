#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_root="$repository/build/probes/tasking"
interface_root="$repository/probes/tasking/interfaces"
mkdir -p "$output_root"

for architecture in x86_64 aarch64; do
    case "$architecture" in
        x86_64) target=x86_64-elf ;;
        aarch64) target=aarch64-elf ;;
    esac
    output="$output_root/$architecture"
    mkdir -p "$output"
    rm -f "$output"/*

    for probe in task_activation_probe identity_probe master_probe \
        chain_exception_probe placement_probe; do
        scripts/toolchain.sh exec-at "$architecture" "$output" \
            "$target-gcc" -c "$repository/probes/tasking/$probe.adb" \
            -o "$probe.o" -nostdinc -I"$interface_root" \
            -gnat2022 -gnatG -gnatf \
            >"$output/$probe.expanded" 2>&1
        scripts/toolchain.sh exec-at "$architecture" "$output" \
            "$target-nm" -u "$probe.o" >"$output/$probe.undefined"
    done

    activation="$output/task_activation_probe.undefined"
    for symbol in \
        system__tasking__activation_chainIP \
        system__tasking__stages__create_task \
        system__tasking__stages__activate_tasks \
        system__tasking__stages__complete_activation \
        system__tasking__stages__complete_task \
        system__soft_links__abort_defer \
        system__soft_links__abort_undefer; do
        grep -F " $symbol" "$activation" >/dev/null
    done
    grep -F 'system__tasking__unspecified_cpu' \
        "$output/task_activation_probe.expanded" >/dev/null
    grep -F '_init._cpu := 1' \
        "$output/task_activation_probe.expanded" >/dev/null
    grep -F 'integer(_init._cpu)' \
        "$output/placement_probe.expanded" >/dev/null

    identity="$output/identity_probe.undefined"
    for symbol in ada__task_identification__current_task \
        ada__task_identification__is_callable \
        ada__task_identification__is_terminated; do
        grep -F " $symbol" "$identity" >/dev/null
    done

    for symbol in system__tasking__stages__activate_tasks \
        system__soft_links__enter_master \
        system__soft_links__current_master \
        system__soft_links__complete_master; do
        grep -F " $symbol" "$output/master_probe.undefined" >/dev/null
    done
    grep -F 'system__soft_links__enter_master.all' \
        "$output/master_probe.expanded" >/dev/null
    grep -F 'system__soft_links__complete_master.all' \
        "$output/master_probe.expanded" >/dev/null
    grep -F 'system__soft_links__complete_master.all' \
        "$output/chain_exception_probe.expanded" >/dev/null
    if grep -Fi 'activation_chainDF' \
        "$output/chain_exception_probe.expanded" >/dev/null; then
        echo 'unexpected controlled activation-chain finalizer' >&2
        exit 1
    fi
    echo "FLYOLOGY:TASKING:PROBE:PASS:$architecture"
done

diff -u \
    "$output_root/x86_64/task_activation_probe.undefined" \
    "$output_root/aarch64/task_activation_probe.undefined" \
    >"$output_root/task-undefined.diff" || {
        if grep -Ev '^[-+]( *U )?(__clear_cache)?$|^[-+]{3}' \
            "$output_root/task-undefined.diff" | grep -E '^[-+]' >/dev/null; then
            echo 'task ABI undefined surfaces differ unexpectedly' >&2
            exit 1
        fi
    }

echo 'FLYOLOGY:TASKING:PROBE:PASS'
