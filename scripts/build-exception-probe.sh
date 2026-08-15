#!/bin/sh
set -eu

test "$#" -eq 1 || {
    echo "usage: $0 x86_64|aarch64" >&2
    exit 64
}

architecture=$1
repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
case "$architecture" in
    x86_64)
        target=x86_64-elf
        architecture_flags='-mno-red-zone -mcmodel=large'
        libgcc_digest=b6d172e843239c3fa3906c0d972936a48ebf3d4249a0d0e723f83ecb18ff2304
        ;;
    aarch64)
        target=aarch64-elf
        architecture_flags='-mcmodel=large -mgeneral-regs-only'
        libgcc_digest=0effb03f768225ce901b94e6ab108a3709b83bd2c879a629136b89b9bb0cd992
        ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

output_directory="build/exception-probe/$architecture"
mkdir -p "$output_directory"
rm -f "$output_directory"/*.ali "$output_directory"/*.o \
      "$output_directory"/b~exception_probe.ad? \
      "$output_directory/flyology-exception-probe.elf"

export LC_ALL=C
export SOURCE_DATE_EPOCH=1786502400

compile_ada() {
    source=$1
    object=$2
    runtime_mode=${3:-no}
    case "$runtime_mode" in
        yes) style_flags='-gnatg -gnat2022 -gnatwa -gnatwe' ;;
        generated) style_flags='-gnat2022 -gnatws' ;;
        no) style_flags='-gnat2022 -gnatwa -gnatwe' ;;
        *) echo "invalid Ada compile mode: $runtime_mode" >&2; exit 64 ;;
    esac
    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "$source" -o "$output_directory/$object" \
        -nostdinc -Isrc/bootstrap -Isrc/primitives -Iprobes/synchronization/interfaces \
        -I"$output_directory" $style_flags -gnatw.X -gnatw.i -gnato \
        -gnatec=config/restrictions/exception-probe.adc \
        -ffunction-sections -fdata-sections \
        -fno-stack-protector -fno-pic -fno-pie $architecture_flags
}

compile_ada src/bootstrap/system.ads system.o yes
compile_ada src/bootstrap/s-stalib.adb s-stalib.o yes
compile_ada src/primitives/flyology.ads flyology.o
compile_ada src/primitives/flyology-validation.adb flyology-validation.o
compile_ada src/primitives/flyology-boot_validation.adb flyology-boot_validation.o
compile_ada src/bootstrap/flyology-binder_support.adb \
    flyology-binder_support.o
compile_ada probes/synchronization/exception_probe.adb exception_probe.o

scripts/toolchain.sh exec-at "$architecture" "$output_directory" \
    "$target-gnatbind" -nostdinc -nostdlib -n -minimal \
    -I"$repository/src/bootstrap" -I"$repository/src/primitives" \
    -I"$repository/probes/synchronization/interfaces" -I. exception_probe.ali

compile_ada "$output_directory/b~exception_probe.adb" \
    b~exception_probe.o generated

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "src/platform/$architecture/entry.S" \
    -o "$output_directory/exception_entry.o" \
    -DFLYOLOGY_EXCEPTIONS -ffreestanding -fno-stack-protector \
    -fno-pic -fno-pie $architecture_flags

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "src/platform/$architecture/limine_requests.S" \
    -o "$output_directory/limine_requests.o" -ffreestanding \
    -fno-stack-protector -fno-pic -fno-pie $architecture_flags

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c src/abi/exception_runtime.c \
    -o "$output_directory/exception_runtime.o" -ffreestanding \
    -fno-stack-protector -fno-pic -fno-pie -fno-builtin \
    -ffunction-sections -fdata-sections -funwind-tables \
    -Wall -Wextra -Werror $architecture_flags

libgcc=$(scripts/toolchain.sh exec "$architecture" \
    "$target-gcc" -print-libgcc-file-name)
printf '%s  %s\n' "$libgcc_digest" "$libgcc" | \
    shasum -a 256 -c - >/dev/null

scripts/toolchain.sh exec "$architecture" "$target-ld" \
    --build-id=none --fatal-warnings --gc-sections -z noexecstack \
    -Map "$output_directory/exception.map" \
    -T "src/platform/$architecture/exception.ld" \
    -o "$output_directory/flyology-exception-probe.elf" \
    "$output_directory/exception_entry.o" \
    "$output_directory/limine_requests.o" \
    "$output_directory/b~exception_probe.o" \
    "$output_directory/exception_probe.o" \
    "$output_directory/exception_runtime.o" \
    "$output_directory/flyology-binder_support.o" \
    "$output_directory/flyology-boot_validation.o" \
    "$output_directory/flyology-validation.o" \
    "$output_directory/flyology.o" \
    "$output_directory/s-stalib.o" \
    "$output_directory/system.o" \
    --start-group "$libgcc" --end-group

test -z "$(scripts/toolchain.sh exec "$architecture" \
    "$target-nm" -u "$output_directory/flyology-exception-probe.elf")"

FLYOLOGY_DISK_OUTPUT_DIRECTORY="$output_directory" \
    scripts/build-disk.sh "$architecture" \
    "$output_directory/flyology-exception-probe.elf"
