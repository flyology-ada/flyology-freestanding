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
    echo "FLYOLOGY:M4:PROBE:PASS:$architecture"
done

diff -u "$output_root/x86_64/exception_probe.undefined" \
    "$output_root/aarch64/exception_probe.undefined" >/dev/null
echo 'FLYOLOGY:M4:PROBE:PASS'
