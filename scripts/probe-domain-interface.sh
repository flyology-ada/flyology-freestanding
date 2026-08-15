#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_root="$repository/build/probes/domains"

for architecture in x86_64 aarch64; do
    case "$architecture" in
        x86_64) target=x86_64-elf ;;
        aarch64) target=aarch64-elf ;;
    esac
    output="$output_root/$architecture"
    rm -rf "$output"
    mkdir -p "$output"

    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c "$repository/probes/domains/domain_probe.adb" \
        -o domain_probe.o -nostdinc \
        -I"$repository/probes/domains/interfaces" \
        -I"$repository/probes/tasking/interfaces" \
        -gnat2022 -gnatG -gnatf \
        -gnatec="$repository/config/restrictions/product.adc" \
        >"$output/domain_probe.expanded" 2>&1
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-nm" -u domain_probe.o >"$output/domain_probe.undefined"
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-objdump" -dr domain_probe.o >"$output/domain_probe.dis"
    scripts/toolchain.sh exec-at "$architecture" "$output" \
        "$target-gcc" -c \
        "$repository/probes/domains/interfaces/s-mudido.ads" \
        -nostdinc \
        -I"$repository/probes/domains/interfaces" \
        -I"$repository/probes/tasking/interfaces" \
        -gnat2022 -gnatc -gnatR3 -gnatf \
        -gnatec="$repository/config/restrictions/product.adc" \
        >"$output/domain_layout.txt" 2>&1

    expanded="$output/domain_probe.expanded"
    undefined="$output/domain_probe.undefined"
    layout="$output/domain_layout.txt"
    grep -F 'createBIPaccess => worker_domain' "$expanded" >/dev/null
    grep -F '_dispatching_domain : system__tasking__dispatching_domain_access' \
        "$expanded" >/dev/null
    grep -F 'system__tasking__dispatching_domain_access!(worker_domain)' \
        "$expanded" >/dev/null
    grep -F 'ada__real_time__time_span_zero, _init._dispatching_domain' \
        "$expanded" >/dev/null
    grep -F '_init._cpu := 2' "$expanded" >/dev/null
    grep -F 'integer(_init._cpu)' "$expanded" >/dev/null
    for shape in \
        "for Dispatching_Domain'Size use 192;" \
        "for Dispatching_Domain'Alignment use 8;" \
        'First      at  8 range  0 .. 31;' \
        'Last       at 12 range  0 .. 31;' \
        'Handle     at  0 range  0 .. 63;' \
        'Identifier at 16 range  0 .. 31;'; do
        grep -F "$shape" "$layout" >/dev/null
    done
    case "$architecture" in
        x86_64)
            grep -F 'mov    (%rax),%rdi' \
                "$output/domain_probe.dis" >/dev/null
            ;;
        aarch64)
            grep -F 'ldr	x0, [x0]' \
                "$output/domain_probe.dis" >/dev/null
            ;;
    esac

    for symbol in \
        system__multiprocessors__dispatching_domains__create \
        system__multiprocessors__dispatching_domains__get_cpu_set \
        system__secondary_stack__ss_mark \
        system__secondary_stack__ss_release \
        system__tasking__stages__create_task \
        system__tasking__stages__activate_tasks \
        system__tasking__stages__complete_activation \
        system__tasking__stages__complete_task; do
        grep -F " $symbol" "$undefined" >/dev/null
    done
    echo "FLYOLOGY:DOMAINS:PROBE:PASS:$architecture"
done

diff -u "$output_root/x86_64/domain_probe.undefined" \
    "$output_root/aarch64/domain_probe.undefined" \
    >"$output_root/domain-undefined.diff" || {
        if grep -Ev '^[-+]( *U )?(__clear_cache)?$|^[-+]{3}' \
            "$output_root/domain-undefined.diff" | grep -E '^[-+]' >/dev/null; then
            echo 'domain ABI undefined surfaces differ unexpectedly' >&2
            exit 1
        fi
    }

echo 'FLYOLOGY:DOMAINS:PROBE:PASS'
