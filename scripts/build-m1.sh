#!/bin/sh
set -eu

test "$#" -eq 1 || {
    echo "usage: $0 x86_64|aarch64" >&2
    exit 64
}

architecture=$1
case "$architecture" in
    x86_64)
        target=x86_64-elf
        architecture_flags="-mno-red-zone -mcmodel=large"
        ;;
    aarch64)
        target=aarch64-elf
        architecture_flags="-mcmodel=large -mgeneral-regs-only"
        ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

variant=${FLYOLOGY_M1_VARIANT:-normal}
case "$variant" in
    normal)
        build_root=build/m1
        assembly_flags=
        ;;
    last-chance)
        build_root=build/m1-last-chance
        assembly_flags=-DFLYOLOGY_M1_FAULT_LAST_CHANCE
        ;;
    *) echo "unsupported M1 variant: $variant" >&2; exit 64 ;;
esac

output_directory="$build_root/$architecture"
mkdir -p "$output_directory"
rm -f "$output_directory"/*.ali "$output_directory"/*.o \
      "$output_directory"/b~flyology_m1.ad? \
      "$output_directory/flyology-m1.elf"

export LC_ALL=C
export SOURCE_DATE_EPOCH=1786502400

compile_ada() {
    source=$1
    object=$2
    runtime_mode=${3:-no}
    case "$runtime_mode" in
        yes) style_flags='-gnatg -gnatwa -gnatwe' ;;
        generated) style_flags='-gnat2022 -gnatws' ;;
        no) style_flags='-gnat2022 -gnatwa -gnatwe' ;;
        *) echo "invalid Ada compile mode: $runtime_mode" >&2; exit 64 ;;
    esac
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "$source" -o "$output_directory/$object" \
        -nostdinc -Isrc/bootstrap -Isrc/primitives -Iruntime/m1 \
        -I"$output_directory" $style_flags -gnatw.X -gnato \
        -gnatec=src/bootstrap/m1.adc \
        -ffunction-sections -fdata-sections \
        -fno-stack-protector -fno-pic -fno-pie $architecture_flags
}

compile_ada src/bootstrap/system.ads system.o yes
compile_ada src/bootstrap/s-stalib.adb s-stalib.o yes
compile_ada src/primitives/flyology.ads flyology.o
compile_ada src/primitives/flyology-validation.adb flyology-validation.o
compile_ada src/primitives/flyology-boot_validation.adb flyology-boot_validation.o
compile_ada src/bootstrap/flyology-binder_support.adb flyology-binder_support.o
compile_ada runtime/m1/flyology-elaboration_probe.adb flyology-elaboration_probe.o
compile_ada runtime/m1/flyology_m1.adb flyology_m1.o
compile_ada runtime/m1/flyology_last_chance_probe.adb \
    flyology_last_chance_probe.o

scripts/toolchain.sh exec-at "$architecture" "$output_directory" \
    "$target-gnatbind" \
    -nostdinc -nostdlib -n -minimal \
    -I../../../src/bootstrap -I../../../src/primitives -I../../../runtime/m1 \
    -I. flyology_m1.ali

compile_ada "$output_directory/b~flyology_m1.adb" b~flyology_m1.o generated

scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "src/platform/$architecture/m1_entry.S" \
    -o "$output_directory/m1_entry.o" \
    -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
    $assembly_flags $architecture_flags

scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "src/platform/$architecture/limine_requests.S" \
    -o "$output_directory/limine_requests.o" \
    -ffreestanding -fno-stack-protector -fno-pic -fno-pie $architecture_flags

scripts/toolchain.sh exec "$architecture" "$target-ld" \
    --build-id=none --fatal-warnings --gc-sections -z noexecstack \
    -T "src/platform/$architecture/m1.ld" \
    -o "$output_directory/flyology-m1.elf" \
    "$output_directory/m1_entry.o" \
    "$output_directory/limine_requests.o" \
    "$output_directory/b~flyology_m1.o" \
    "$output_directory/flyology_m1.o" \
    "$output_directory/flyology_last_chance_probe.o" \
    "$output_directory/flyology-elaboration_probe.o" \
    "$output_directory/flyology-binder_support.o" \
    "$output_directory/flyology-boot_validation.o" \
    "$output_directory/flyology-validation.o" \
    "$output_directory/flyology.o" \
    "$output_directory/s-stalib.o" \
    "$output_directory/system.o"

unresolved=$(scripts/toolchain.sh exec "$architecture" \
    "$target-nm" -u "$output_directory/flyology-m1.elf")
test -z "$unresolved" || {
    printf '%s\n' "$unresolved" >&2
    exit 1
}

FLYOLOGY_DISK_OUTPUT_DIRECTORY="$output_directory" \
    scripts/build-disk.sh "$architecture" "$output_directory/flyology-m1.elf"
