#!/bin/sh
set -eu

usage() {
    echo "usage: $0 x86_64|aarch64 [OUTPUT_DIRECTORY]" >&2
    exit 64
}

test "$#" -ge 1 && test "$#" -le 2 || usage
architecture=$1
output_directory=${2:-build/bootstrap-minimum/$architecture}

case "$architecture" in
    x86_64)
        target=x86_64-elf
        entry=src/platform/x86_64/minimal_boot_entry.S
        linker_script=src/platform/x86_64/minimal_boot.ld
        architecture_flags="-mno-red-zone -mcmodel=kernel"
        ;;
    aarch64)
        target=aarch64-elf
        entry=src/platform/aarch64/minimal_boot_entry.S
        linker_script=src/platform/aarch64/minimal_boot.ld
        architecture_flags="-mgeneral-regs-only"
        ;;
    *)
        usage
        ;;
esac

mkdir -p "$output_directory"
rm -f "$output_directory/flyology-bootstrap-minimum.elf" \
      "$output_directory/flyology_bootstrap_minimum.o" \
      "$output_directory/minimal_boot_entry.o"

export LC_ALL=C
export SOURCE_DATE_EPOCH=1786502400

scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c tests/platform/bootstrap-minimum/flyology_bootstrap_minimum.adb \
    -o "$output_directory/flyology_bootstrap_minimum.o" \
    -nostdinc -Isrc/bootstrap \
    -gnat2022 -gnatp -gnatws \
    -fno-stack-protector -fno-pic -fno-pie \
    $architecture_flags

scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "$entry" -o "$output_directory/minimal_boot_entry.o" \
    -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
    $architecture_flags

scripts/toolchain.sh exec "$architecture" "$target-ld" \
    --build-id=none --fatal-warnings -z noexecstack \
    -T "$linker_script" \
    -o "$output_directory/flyology-bootstrap-minimum.elf" \
    "$output_directory/minimal_boot_entry.o" "$output_directory/flyology_bootstrap_minimum.o"
