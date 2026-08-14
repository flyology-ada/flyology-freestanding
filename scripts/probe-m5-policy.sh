#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_root="$repository/build/probes/m5"

for architecture in x86_64 aarch64; do
    case "$architecture" in
        x86_64) target=x86_64-elf ;;
        aarch64) target=aarch64-elf ;;
    esac
    for policy in fifo round_robin; do
        output="$output_root/$architecture/$policy"
        rm -rf "$output"
        mkdir -p "$output"

        scripts/toolchain.sh exec-at "$architecture" "$output" \
            "$target-gcc" -c "$repository/runtime/bootstrap/system.ads" \
            -o system.o -nostdinc -I"$repository/runtime/bootstrap" \
            -gnat2022 -gnatg -gnatf \
            -gnatec="$repository/probes/m5/$policy.adc"
        scripts/toolchain.sh exec-at "$architecture" "$output" \
            "$target-gcc" -c "$repository/runtime/bootstrap/s-stalib.adb" \
            -o s-stalib.o -nostdinc -I"$repository/runtime/bootstrap" \
            -gnat2022 -gnatg -gnatf \
            -gnatec="$repository/probes/m5/$policy.adc"
        scripts/toolchain.sh exec-at "$architecture" "$output" \
            "$target-gcc" -c "$repository/probes/m5/policy_probe.adb" \
            -o policy_probe.o -nostdinc -I"$repository/runtime/bootstrap" \
            -gnat2022 -gnatf -gnatec="$repository/probes/m5/$policy.adc"

        if test "$policy" = round_robin; then
            time_slice=-T10
            expected_policy=R
            expected_slice=10000
        else
            time_slice=-T0
            expected_policy=F
            expected_slice=0
        fi
        scripts/toolchain.sh exec-at "$architecture" "$output" \
            "$target-gnatbind" -nostdinc -nostdlib -n -minimal \
            "$time_slice" -I"$repository/runtime/bootstrap" -I. \
            -o b~policy_probe.adb policy_probe.ali

        grep -F "Time_Slice_Value := $expected_slice;" \
            "$output/b~policy_probe.adb" >/dev/null
        grep -F "Task_Dispatching_Policy := '$expected_policy';" \
            "$output/b~policy_probe.adb" >/dev/null
        grep -F 'Num_Specific_Dispatching := 0;' \
            "$output/b~policy_probe.adb" >/dev/null
    done
done

echo FLYOLOGY:M5:POLICY_PROBE:PASS
