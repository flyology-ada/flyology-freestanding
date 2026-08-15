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

output_root=${FLYOLOGY_M6_OUTPUT_ROOT:-build/m6}
elf="$output_root/$architecture/flyology-m3.elf"
binder="$output_root/$architecture/b~flyology_conformance.adb"
test -f "$elf"
test -f "$binder"

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
    echo "forbidden hosted, TLS, dynamic, or RWX M6 ELF state" >&2
    exit 1
fi

for symbol in _start adainit adafinal _ada_flyology_conformance \
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
    flyology__rts__register_domain_alias \
    flyology__rts__create_domain \
    flyology__kernel__try_create_domain_locked \
    flyology__kernel__activate_locked \
    flyology__domain_model__valid flyology__domain_model__try_create \
    flyology__domain_model__place flyology__domain_model__try_admit \
    flyology_m5_preemption_canary; do
    printf '%s\n' "$nm_output" | grep -E "[[:space:]]$symbol$" >/dev/null
done

test -z "$(scripts/toolchain.sh exec "$architecture" "$target-nm" -u "$elf")"
if printf '%s\n' "$nm_output" | \
    grep -Ei '[[:space:]]([^[:space:]]*(spawn|fiber)|__clear_cache)$' >/dev/null; then
    echo "forbidden alternate task API, fiber, or cache trampoline" >&2
    exit 1
fi

strings_output=$(scripts/toolchain.sh exec "$architecture" "$target-strings" "$elf")
for marker in DOMAIN_LAYOUT STANDARD_QUERIES DOMAIN_INHERITANCE \
    HETEROGENEOUS_POLICY ALL_CORE_PREEMPTION; do
    printf '%s\n' "$strings_output" | \
        grep -F "FLYOLOGY:M6:$marker:PASS" >/dev/null
done

grep -F 'Task_Dispatching_Policy := '\''F'\'';' "$binder" >/dev/null
grep -F 'Time_Slice_Value := 0;' "$binder" >/dev/null
grep -F '__gnat_freeze_dispatching_domains' "$binder" >/dev/null

echo "FLYOLOGY:M6:INSPECT:PASS:$architecture"
