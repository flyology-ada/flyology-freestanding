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
output_directory=$(CDPATH= cd -- "$output_directory" && pwd)
probe_config="$repository/config/restrictions/exception-probe.adc"

export LC_ALL=C
export SOURCE_DATE_EPOCH=1786502400

scripts/toolchain.sh exec "$architecture" sh -c '
    target=$1
    architecture=$2
    object_directory=$3
    probe_config=$4
    driver=$(command -v "$target-gcc")
    archiver=$(command -v "$target-ar")
    archive_indexer=$(command -v "$target-ranlib")
    exec gprbuild -c -p -P gpr/flyology_exception_probe.gpr \
        --config=gpr/flyology_cross.cgpr \
        -XFLYOLOGY_TARGET="$target" \
        -XFLYOLOGY_ADA_DRIVER="$driver" \
        -XFLYOLOGY_ARCHIVER="$archiver" \
        -XFLYOLOGY_ARCHIVE_INDEXER="$archive_indexer" \
        -XFLYOLOGY_ARCHITECTURE="$architecture" \
        -XFLYOLOGY_OBJECT_DIR="$object_directory" \
        -XFLYOLOGY_PROBE_CONFIG="$probe_config"
' sh "$target" "$architecture" "$output_directory" "$probe_config"

ada_objects_file="$output_directory/ada-objects.list"
find "$output_directory" -maxdepth 1 -type f -name '*.o' -print | \
    LC_ALL=C sort >"$ada_objects_file"

scripts/toolchain.sh exec-at "$architecture" "$output_directory" \
    "$target-gnatbind" -nostdinc -nostdlib -n -minimal \
    -I"$repository/src/bootstrap" -I"$repository/src/primitives" \
    -I"$repository/probes/synchronization" -I. exception_probe.ali

#  Binder output is the sole Ada source compiled outside the project graph.
# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "$output_directory/b~exception_probe.adb" \
    -o "$output_directory/b~exception_probe.o" \
    -nostdinc -Isrc/bootstrap -Isrc/primitives -Iprobes/synchronization \
    -I"$output_directory" -gnat2022 -gnatws -gnatw.X -gnatw.i -gnato \
    -gnatec="$probe_config" -ffunction-sections -fdata-sections \
    -fno-stack-protector -fno-pic -fno-pie $architecture_flags

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

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c tests/platform/exception-boundary/allocator_lock.c \
    -o "$output_directory/allocator_lock.o" -ffreestanding \
    -fno-stack-protector -fno-pic -fno-pie -fno-builtin \
    -ffunction-sections -fdata-sections \
    -Wall -Wextra -Werror $architecture_flags

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c src/abi/allocator_runtime.c \
    -o "$output_directory/allocator_runtime.o" -ffreestanding \
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
    "$output_directory/exception_runtime.o" \
    "$output_directory/allocator_runtime.o" \
    "$output_directory/allocator_lock.o" \
    @"$ada_objects_file" \
    --start-group "$libgcc" --end-group

test -z "$(scripts/toolchain.sh exec "$architecture" \
    "$target-nm" -u "$output_directory/flyology-exception-probe.elf")"

FLYOLOGY_DISK_OUTPUT_DIRECTORY="$output_directory" \
    scripts/build-disk.sh "$architecture" \
    "$output_directory/flyology-exception-probe.elf"
