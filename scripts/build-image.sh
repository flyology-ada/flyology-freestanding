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

output_root=${FLYOLOGY_IMAGE_OUTPUT_ROOT:-build/image}
output_directory="$output_root/$architecture"
product_config=${FLYOLOGY_PRODUCT_CONFIG:-config/restrictions/product.adc}
binder_flags=${FLYOLOGY_BINDER_FLAGS:-}
assembly_defines='-DFLYOLOGY_INTERRUPTS -DFLYOLOGY_TASKING -DFLYOLOGY_EXCEPTIONS'
test_observations=${FLYOLOGY_TEST_OBSERVATIONS:-1}
case "$test_observations" in
    0) ;;
    1) assembly_defines="$assembly_defines -DFLYOLOGY_TEST_OBSERVATIONS" ;;
    *) echo "unsupported test-observation setting: $test_observations" >&2; exit 64 ;;
esac
domain_config_dir=${FLYOLOGY_DOMAIN_CONFIG_DIR:-config/domains/off}
conformance_config_dir=${FLYOLOGY_CONFORMANCE_CONFIG_DIR:-tests/target/config/domains/off}
application_dir=${FLYOLOGY_APPLICATION_DIR:-tests/target/scenarios}
application_unit=${FLYOLOGY_APPLICATION_UNIT:-flyology_conformance}
application_source="$application_unit.adb"
printf '%s\n' "$application_unit" | grep -Eq '^[a-z][a-z0-9_]*$' || {
    echo "invalid Ada application unit: $application_unit" >&2
    exit 64
}
case "$application_unit" in
    *_|*__*) echo "invalid Ada application unit: $application_unit" >&2; exit 64 ;;
esac
if test "${FLYOLOGY_DOMAINS:-0}" = 1; then
    assembly_defines="$assembly_defines -DFLYOLOGY_DOMAINS"
fi
mkdir -p "$output_directory"
rm -f "$output_directory"/*.ali "$output_directory"/*.o \
      "$output_directory"/b~"$application_unit".ad? \
      "$output_directory"/b~flyology_launcher.ad? \
      "$output_directory/flyology.elf"
output_directory=$(CDPATH= cd -- "$output_directory" && pwd)

absolute_path() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$repository" "$1" ;;
    esac
}

domain_config_directory=$(absolute_path "$domain_config_dir")
conformance_config_directory=$(absolute_path "$conformance_config_dir")
case "$application_dir" in
    /*) application_directory=$application_dir ;;
    *) application_directory=$(CDPATH= cd -- "$application_dir" && pwd) ;;
esac
product_config_file=$(absolute_path "$product_config")
test -f "$application_directory/$application_source" || {
    echo "missing application main: $application_directory/$application_source" >&2
    exit 66
}
sed "s/@APPLICATION_UNIT@/$application_unit/g" \
    "$repository/src/application/flyology_launcher.adb.in" > \
    "$output_directory/flyology_launcher.adb"

export LC_ALL=C
export SOURCE_DATE_EPOCH=1786502400

#  The GPR project owns the complete Ada dependency closure.  The shell keeps
#  only the compiler path supplied by the pinned Alire environment and the
#  external configuration views selected for this image.
scripts/toolchain.sh exec "$architecture" sh -c '
    target=$1
    architecture=$2
    object_directory=$3
    domain_directory=$4
    conformance_directory=$5
    application_directory=$6
    generated_directory=$7
    product_config=$8
    driver=$(command -v "$target-gcc")
    archiver=$(command -v "$target-ar")
    archive_indexer=$(command -v "$target-ranlib")
    exec gprbuild -c -p -P gpr/flyology_image.gpr \
        --config=gpr/flyology_cross.cgpr \
        -XFLYOLOGY_TARGET="$target" \
        -XFLYOLOGY_ADA_DRIVER="$driver" \
        -XFLYOLOGY_ARCHIVER="$archiver" \
        -XFLYOLOGY_ARCHIVE_INDEXER="$archive_indexer" \
        -XFLYOLOGY_ARCHITECTURE="$architecture" \
        -XFLYOLOGY_OBJECT_DIR="$object_directory" \
        -XFLYOLOGY_DOMAIN_CONFIG_DIR="$domain_directory" \
        -XFLYOLOGY_CONFORMANCE_CONFIG_DIR="$conformance_directory" \
        -XFLYOLOGY_APPLICATION_DIR="$application_directory" \
        -XFLYOLOGY_GENERATED_DIR="$generated_directory" \
        -XFLYOLOGY_PRODUCT_CONFIG="$product_config"
' sh "$target" "$architecture" "$output_directory" \
    "$domain_config_directory" \
    "$conformance_config_directory" "$application_directory" \
    "$output_directory" "$product_config_file"

ada_objects_file="$output_directory/ada-objects.list"
find "$output_directory" -maxdepth 1 -type f -name '*.o' -print | \
    LC_ALL=C sort >"$ada_objects_file"

scripts/toolchain.sh exec-at "$architecture" "$output_directory" \
    "$target-gnatbind" -nostdinc -nostdlib -n -minimal \
    -I"$repository/src/bootstrap" -I"$repository/src/primitives" \
    -I"$repository/src/abi" \
    -I"$repository/src/kernel" -I"$repository/src/rts" \
    -I"$repository/src/gnarl" -I"$domain_config_directory" \
    -I"$conformance_config_directory" \
    -I"$output_directory" \
    -I"$application_directory" \
    -I"$repository/src/platform/$architecture" \
    -I. $binder_flags flyology_launcher.ali

policy_code=$(sed -n \
    "s/.*Task_Dispatching_Policy := '\\(.\\)';.*/\\1/p" \
    "$output_directory/b~flyology_launcher.adb")
case "$policy_code" in
    F|R) assembly_defines="$assembly_defines -DFLYOLOGY_PREEMPTION" ;;
    ' ')
        if test "${FLYOLOGY_REQUIRE_APPLICATION_POLICY:-0}" = 1; then
            echo 'application must declare pragma Task_Dispatching_Policy' >&2
            exit 65
        fi
        ;;
    '') echo 'binder omitted task dispatching policy assignment' >&2; exit 65 ;;
    *) echo "unsupported binder task dispatching policy: $policy_code" >&2; exit 65 ;;
esac

#  Binder output is generated after the project build and is the only Ada
#  source compiled outside the project dependency graph.
# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "$output_directory/b~flyology_launcher.adb" \
    -o "$output_directory/b~flyology_launcher.o" \
    -nostdinc -Isrc/bootstrap -Isrc/primitives -Isrc/abi \
    -Isrc/kernel -Isrc/rts \
    -Isrc/gnarl -Isrc/application \
    -I"$domain_config_directory" -I"$conformance_config_directory" \
    -I"$application_directory" -I"$output_directory" \
    -I"src/platform/$architecture" -I"$output_directory" \
    -gnat2022 -gnatws -gnatw.X -gnatw.i -gnato \
    -gnatec="$product_config_file" -ffunction-sections -fdata-sections \
    -fno-stack-protector -fno-pic -fno-pie $architecture_flags

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "src/platform/$architecture/entry.S" -o "$output_directory/entry.o" \
    $assembly_defines -ffreestanding \
    -fno-stack-protector -fno-pic -fno-pie $architecture_flags

for source in context memory limine_requests; do
    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "src/platform/$architecture/$source.S" \
        -o "$output_directory/$source.o" \
        -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
        $architecture_flags
done

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c src/abi/exception_runtime.c \
    -o "$output_directory/exception_runtime.o" -ffreestanding \
    -DFLYOLOGY_RUNTIME_MEMORY_EXTERNAL \
    -fno-stack-protector -fno-pic -fno-pie -fno-builtin \
    -ffunction-sections -fdata-sections -funwind-tables \
    -Wall -Wextra -Werror $architecture_flags

libgcc=$(scripts/toolchain.sh exec "$architecture" \
    "$target-gcc" -print-libgcc-file-name)
printf '%s  %s\n' "$libgcc_digest" "$libgcc" | \
    shasum -a 256 -c - >/dev/null

scripts/toolchain.sh exec "$architecture" "$target-ld" \
    --build-id=none --fatal-warnings --gc-sections -z noexecstack \
    -T "src/platform/$architecture/image.ld" \
    -o "$output_directory/flyology.elf" \
    "$output_directory/entry.o" \
    "$output_directory/context.o" \
    "$output_directory/memory.o" \
    "$output_directory/limine_requests.o" \
    "$output_directory/exception_runtime.o" \
    "$output_directory/b~flyology_launcher.o" \
    @"$ada_objects_file" \
    --start-group "$libgcc" --end-group

test -z "$(scripts/toolchain.sh exec "$architecture" \
    "$target-nm" -u "$output_directory/flyology.elf")"

FLYOLOGY_DISK_OUTPUT_DIRECTORY="$output_directory" \
    scripts/build-disk.sh "$architecture" \
    "$output_directory/flyology.elf"
