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
        architecture_flags='-mno-red-zone -mcmodel=large'
        ;;
    aarch64)
        target=aarch64-elf
        architecture_flags='-mcmodel=large -mgeneral-regs-only'
        ;;
    *)
        echo "unsupported architecture: $architecture" >&2
        exit 64
        ;;
esac

output_directory="build/m2/$architecture"
mkdir -p "$output_directory"
rm -f "$output_directory"/*.ali "$output_directory"/*.o \
      "$output_directory"/b~flyology_m2.ad? \
      "$output_directory/flyology-m2.elf"

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
    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "$source" -o "$output_directory/$object" \
        -nostdinc -Isrc/bootstrap -Isrc/primitives \
        -Itests/legacy/checkpoints/m2 \
        -I"src/platform/$architecture" -I"$output_directory" \
        $style_flags -gnatw.X -gnato -gnatec=config/restrictions/bootstrap.adc \
        -ffunction-sections -fdata-sections \
        -fno-stack-protector -fno-pic -fno-pie $architecture_flags
}

compile_ada src/bootstrap/system.ads system.o yes
compile_ada src/bootstrap/s-stalib.adb s-stalib.o yes
compile_ada src/primitives/flyology.ads flyology.o
compile_ada src/primitives/flyology-validation.adb flyology-validation.o
compile_ada src/primitives/flyology-boot_validation.adb flyology-boot_validation.o
compile_ada src/primitives/flyology-dispatcher_model.adb \
    flyology-dispatcher_model.o
compile_ada src/primitives/flyology-reschedule_model.adb \
    flyology-reschedule_model.o
compile_ada src/primitives/flyology-scheduler_contract.adb \
    flyology-scheduler_contract.o
compile_ada src/primitives/flyology-clock_model.adb flyology-clock_model.o
compile_ada "src/platform/$architecture/flyology-architecture_context.ads" \
    flyology-architecture_context.o
compile_ada "src/platform/$architecture/flyology-interrupt_frames.ads" \
    flyology-interrupt_frames.o
compile_ada "src/platform/$architecture/flyology-platform.adb" \
    flyology-platform.o
compile_ada tests/legacy/checkpoints/m2/flyology-m2_runtime.adb \
    flyology-m2_runtime.o
compile_ada src/bootstrap/flyology-binder_support.adb \
    flyology-binder_support.o
compile_ada tests/legacy/checkpoints/m2/flyology_m2.adb flyology_m2.o

scripts/toolchain.sh exec-at "$architecture" "$output_directory" \
    "$target-gnatbind" \
    -nostdinc -nostdlib -n -minimal \
    -I../../../src/bootstrap -I../../../src/primitives \
    -I../../../tests/legacy/checkpoints/m2 \
    -I../../../src/platform/"$architecture" \
    -I. flyology_m2.ali

compile_ada "$output_directory/b~flyology_m2.adb" b~flyology_m2.o generated

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "src/platform/$architecture/entry.S" \
    -o "$output_directory/m2_entry.o" \
    -DFLYOLOGY_M2 -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
    $architecture_flags

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "src/platform/$architecture/context.S" \
    -o "$output_directory/context.o" \
    -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
    $architecture_flags

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "src/platform/$architecture/memory.S" \
    -o "$output_directory/memory.o" \
    -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
    $architecture_flags

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "src/platform/$architecture/limine_requests.S" \
    -o "$output_directory/limine_requests.o" \
    -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
    $architecture_flags

scripts/toolchain.sh exec "$architecture" "$target-ld" \
    --build-id=none --fatal-warnings --gc-sections -z noexecstack \
    -T "src/platform/$architecture/image.ld" \
    -o "$output_directory/flyology-m2.elf" \
    "$output_directory/m2_entry.o" \
    "$output_directory/context.o" \
    "$output_directory/memory.o" \
    "$output_directory/limine_requests.o" \
    "$output_directory/b~flyology_m2.o" \
    "$output_directory/flyology_m2.o" \
    "$output_directory/flyology-m2_runtime.o" \
    "$output_directory/flyology-platform.o" \
    "$output_directory/flyology-architecture_context.o" \
    "$output_directory/flyology-interrupt_frames.o" \
    "$output_directory/flyology-clock_model.o" \
    "$output_directory/flyology-scheduler_contract.o" \
    "$output_directory/flyology-reschedule_model.o" \
    "$output_directory/flyology-dispatcher_model.o" \
    "$output_directory/flyology-binder_support.o" \
    "$output_directory/flyology-boot_validation.o" \
    "$output_directory/flyology-validation.o" \
    "$output_directory/flyology.o" \
    "$output_directory/s-stalib.o" \
    "$output_directory/system.o"

unresolved=$(scripts/toolchain.sh exec "$architecture" \
    "$target-nm" -u "$output_directory/flyology-m2.elf")
test -z "$unresolved" || {
    printf '%s\n' "$unresolved" >&2
    exit 1
}

FLYOLOGY_DISK_OUTPUT_DIRECTORY="$output_directory" \
    scripts/build-disk.sh "$architecture" \
    "$output_directory/flyology-m2.elf"
