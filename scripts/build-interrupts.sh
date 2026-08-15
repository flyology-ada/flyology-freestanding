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

output_directory="build/interrupts/$architecture"
mkdir -p "$output_directory"
rm -f "$output_directory"/*.ali "$output_directory"/*.o \
      "$output_directory"/b~flyology_freestanding_interrupt_checkpoint.ad? \
      "$output_directory/flyology_freestanding-interrupts.elf"

export LC_ALL=C
export SOURCE_DATE_EPOCH=1786502400

compile_ada() {
    source=$1
    object=$2
    runtime_mode=${3:-no}
    case "$runtime_mode" in
        yes) style_flags='-gnatg -gnatyM120 -gnatwa -gnatwe' ;;
        generated) style_flags='-gnat2022 -gnatws' ;;
        no) style_flags='-gnat2022 -gnatwa -gnatwe' ;;
        *) echo "invalid Ada compile mode: $runtime_mode" >&2; exit 64 ;;
    esac
    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "$source" -o "$output_directory/$object" \
        -nostdinc -Isrc/bootstrap -Isrc/primitives \
        -Itests/platform/interrupts \
        -I"src/platform/$architecture" -I"$output_directory" \
        $style_flags -gnatw.X -gnato -gnatec=config/restrictions/bootstrap.adc \
        -ffunction-sections -fdata-sections \
        -fno-stack-protector -fno-pic -fno-pie $architecture_flags
}

compile_ada src/bootstrap/system.ads system.o yes
compile_ada src/bootstrap/s-stalib.adb s-stalib.o yes
compile_ada src/primitives/flyology_freestanding.ads flyology_freestanding.o
compile_ada src/primitives/flyology_freestanding-validation.adb flyology_freestanding-validation.o
compile_ada src/primitives/flyology_freestanding-boot_validation.adb flyology_freestanding-boot_validation.o
compile_ada src/primitives/flyology_freestanding-dispatcher_model.adb \
    flyology_freestanding-dispatcher_model.o
compile_ada src/primitives/flyology_freestanding-reschedule_model.adb \
    flyology_freestanding-reschedule_model.o
compile_ada src/primitives/flyology_freestanding-scheduler_contract.adb \
    flyology_freestanding-scheduler_contract.o
compile_ada src/primitives/flyology_freestanding-clock_model.adb flyology_freestanding-clock_model.o
compile_ada "src/platform/$architecture/flyology_freestanding-architecture_context.ads" \
    flyology_freestanding-architecture_context.o
compile_ada "src/platform/$architecture/flyology_freestanding-interrupt_frames.ads" \
    flyology_freestanding-interrupt_frames.o
compile_ada "src/platform/$architecture/flyology_freestanding-platform.adb" \
    flyology_freestanding-platform.o
compile_ada tests/platform/interrupts/flyology_freestanding-interrupt_checkpoint_runtime.adb \
    flyology_freestanding-interrupt_checkpoint_runtime.o
compile_ada src/bootstrap/flyology_freestanding-binder_support.adb \
    flyology_freestanding-binder_support.o
compile_ada tests/platform/interrupts/flyology_freestanding_interrupt_checkpoint.adb flyology_freestanding_interrupt_checkpoint.o

scripts/toolchain.sh exec-at "$architecture" "$output_directory" \
    "$target-gnatbind" \
    -nostdinc -nostdlib -n -minimal \
    -I../../../src/bootstrap -I../../../src/primitives \
    -I../../../tests/platform/interrupts \
    -I../../../src/platform/"$architecture" \
    -I. flyology_freestanding_interrupt_checkpoint.ali

compile_ada "$output_directory/b~flyology_freestanding_interrupt_checkpoint.adb" b~flyology_freestanding_interrupt_checkpoint.o generated

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "src/platform/$architecture/entry.S" \
    -o "$output_directory/entry.o" \
    -DFLYOLOGY_FREESTANDING_INTERRUPTS -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
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
    -o "$output_directory/flyology_freestanding-interrupts.elf" \
    "$output_directory/entry.o" \
    "$output_directory/context.o" \
    "$output_directory/memory.o" \
    "$output_directory/limine_requests.o" \
    "$output_directory/b~flyology_freestanding_interrupt_checkpoint.o" \
    "$output_directory/flyology_freestanding_interrupt_checkpoint.o" \
    "$output_directory/flyology_freestanding-interrupt_checkpoint_runtime.o" \
    "$output_directory/flyology_freestanding-platform.o" \
    "$output_directory/flyology_freestanding-architecture_context.o" \
    "$output_directory/flyology_freestanding-interrupt_frames.o" \
    "$output_directory/flyology_freestanding-clock_model.o" \
    "$output_directory/flyology_freestanding-scheduler_contract.o" \
    "$output_directory/flyology_freestanding-reschedule_model.o" \
    "$output_directory/flyology_freestanding-dispatcher_model.o" \
    "$output_directory/flyology_freestanding-binder_support.o" \
    "$output_directory/flyology_freestanding-boot_validation.o" \
    "$output_directory/flyology_freestanding-validation.o" \
    "$output_directory/flyology_freestanding.o" \
    "$output_directory/s-stalib.o" \
    "$output_directory/system.o"

unresolved=$(scripts/toolchain.sh exec "$architecture" \
    "$target-nm" -u "$output_directory/flyology_freestanding-interrupts.elf")
test -z "$unresolved" || {
    printf '%s\n' "$unresolved" >&2
    exit 1
}

FLYOLOGY_FREESTANDING_DISK_OUTPUT_DIRECTORY="$output_directory" \
    scripts/build-disk.sh "$architecture" \
    "$output_directory/flyology_freestanding-interrupts.elf"
