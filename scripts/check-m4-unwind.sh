#!/bin/sh
set -eu

test "$#" -eq 1 || {
    echo "usage: $0 x86_64|aarch64" >&2
    exit 64
}

architecture=$1
output_root=${FLYOLOGY_M3_OUTPUT_ROOT:-build/m3}
profile=${FLYOLOGY_UNWIND_PROFILE:-m4}
case "$architecture" in
    x86_64|aarch64) target=$architecture-elf ;;
    *) exit 64 ;;
esac
case "$profile" in
    m4|m6) : ;;
    *) exit 64 ;;
esac

elf="$output_root/$architecture/flyology-m3.elf"
runtime="$output_root/$architecture/exception_runtime.o"
test -f "$elf"
test -f "$runtime"

nm_output=$(scripts/toolchain.sh exec "$architecture" "$target-nm" -n "$elf")
root=$(printf '%s\n' "$nm_output" | awk \
    '$3 == "flyology_task_root_invoke" { print $1 }')
gnat_malloc=$(printf '%s\n' "$nm_output" | awk \
    '$3 == "__gnat_malloc" { print $1 }')
gnat_free=$(printf '%s\n' "$nm_output" | awk \
    '$3 == "__gnat_free" { print $1 }')
frame_start=$(printf '%s\n' "$nm_output" | awk \
    '$3 == "__eh_frame_start" { print $1 }')
frame_end=$(printf '%s\n' "$nm_output" | awk \
    '$3 == "__eh_frame_end" { print $1 }')
test -n "$root"
if test "$profile" = m4; then
    test -n "$gnat_malloc"
    test -n "$gnat_free"
fi
test -n "$frame_start"
test -n "$frame_end"
test "$frame_start" != "$frame_end"

sections=$(scripts/toolchain.sh exec "$architecture" \
    "$target-readelf" -SW "$elf")
set -- $(printf '%s\n' "$sections" | awk '
    { for (field = 1; field <= NF; field++)
        if ($field == ".eh_frame")
            print $(field + 2), $(field + 4) }')
test "$#" -eq 2
section_start=$1
section_size=$2
section_end=$(printf '%x' "$((16#$section_start + 16#$section_size))")
test "$(printf '%s' "$frame_start" | sed 's/^0*//')" = \
    "$(printf '%s' "$section_start" | sed 's/^0*//')"
test "$(printf '%s' "$frame_end" | sed 's/^0*//')" = \
    "$(printf '%s' "$section_end" | sed 's/^0*//')"

frames=$(scripts/toolchain.sh exec "$architecture" \
    "$target-objdump" --dwarf=frames "$elf")
root_line=$(printf '%s\n' "$frames" | grep -F \
    "FDE cie=" | grep -F "pc=$root.." || true)
test "$(printf '%s\n' "$root_line" | grep -c .)" -eq 1
if test "$profile" = m4; then
    malloc_line=$(printf '%s\n' "$frames" | grep -F \
        "FDE cie=" | grep -F "pc=$gnat_malloc.." || true)
    test "$(printf '%s\n' "$malloc_line" | grep -c .)" -eq 1
    free_line=$(printf '%s\n' "$frames" | grep -F \
        "FDE cie=" | grep -F "pc=$gnat_free.." || true)
    test "$(printf '%s\n' "$free_line" | grep -c .)" -eq 1
fi
printf '%s\n' "$frames" | grep -F -A2 "$root_line" | \
    grep -F 'Augmentation data:' >/dev/null
test "$(printf '%s\n' "$frames" | grep -c 'ZERO terminator')" -eq 1
test "$(printf '%s\n' "$frames" | tail -3 | grep -c 'ZERO terminator')" -eq 1

relocations=$(scripts/toolchain.sh exec "$architecture" \
    "$target-objdump" -r "$runtime")
test "$(printf '%s\n' "$relocations" | \
    grep -c '[[:space:]]__eh_frame_start$')" -eq 1
test "$(printf '%s\n' "$relocations" | \
    grep -c '[[:space:]]flyology_task_root_invoke$')" -eq 1
test "$(printf '%s\n' "$relocations" | \
    grep -c '__eh_frame_probe_start')" -eq 0

all_relocations=$(scripts/toolchain.sh exec "$architecture" \
    "$target-objdump" -r "$output_root/$architecture"/*.o)
registration_count=$(printf '%s\n' "$all_relocations" | awk \
    '$NF == "__register_frame" { count = count + 1 } END { print count + 0 }')
test "$registration_count" -eq 1

runtime_ada="$output_root/$architecture/flyology-rts.o"
root_section=.gcc_except_table.flyology_task_root_invoke
root_sections=$(scripts/toolchain.sh exec "$architecture" \
    "$target-readelf" -SW "$runtime_ada")
root_flags=$(printf '%s\n' "$root_sections" | awk -v name="$root_section" '
    { for (field = 1; field <= NF; field++)
        if ($field == name)
            print $(field + 6) }')
test -n "$root_flags"
case "$root_flags" in *A*) : ;; *) exit 1 ;; esac
case "$root_flags" in *W*) exit 1 ;; *) : ;; esac
root_relocations=$(scripts/toolchain.sh exec "$architecture" \
    "$target-objdump" -r -j "$root_section" "$runtime_ada")
test "$(printf '%s\n' "$root_relocations" | \
    grep -Ec '[[:space:]](DW.ref.)?__gnat_others_value$')" -eq 1
if printf '%s\n' "$root_relocations" | \
    grep -F 'DW.ref.__gnat_others_value' >/dev/null; then
    all_runtime_relocations=$(scripts/toolchain.sh exec "$architecture" \
        "$target-objdump" -r "$runtime_ada")
    test "$(printf '%s\n' "$all_runtime_relocations" | \
        grep -c '[[:space:]]__gnat_others_value$')" -eq 1
fi

if test "$profile" = m4; then
    demo="$output_root/$architecture/flyology-conformance-tasking.o"
    demo_disassembly=$(scripts/toolchain.sh exec "$architecture" \
        "$target-objdump" -dr "$demo")
    save_context=$(printf '%s\n' "$demo_disassembly" | \
        grep -B3 -A1 'system__soft_links__save_library_occurrence')
    test "$(printf '%s\n' "$save_context" | \
        grep -Ec 'mov.*0.*(rdi|x0)|mov[[:space:]]+x0, #0')" -ge 1
fi

echo "FLYOLOGY:${profile}:UNWIND:PASS:$architecture" | tr '[:lower:]' '[:upper:]'
