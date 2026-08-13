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
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

output_directory="build/m3/$architecture"
mkdir -p "$output_directory"
rm -f "$output_directory"/*.ali "$output_directory"/*.o \
      "$output_directory"/b~flyology_m3.ad? \
      "$output_directory/flyology-m3.elf"

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
        -nostdinc -Iruntime/bootstrap -Iruntime/core -Iruntime/m3 \
        -I"arch/$architecture" -I"$output_directory" \
        $style_flags -gnatw.X -gnatw.i -gnato \
        -gnatec=runtime/bootstrap/m1.adc \
        -ffunction-sections -fdata-sections \
        -fno-stack-protector -fno-pic -fno-pie $architecture_flags
}

compile_ada runtime/bootstrap/system.ads system.o yes
compile_ada runtime/bootstrap/s-stalib.adb s-stalib.o yes
compile_ada runtime/m3/ada.ads ada.o yes
compile_ada runtime/m3/a-reatim.ads a-reatim.o yes
compile_ada runtime/m3/s-parame.ads s-parame.o yes
compile_ada runtime/m3/s-tasinf.ads s-tasinf.o yes
compile_ada runtime/m3/s-taskin.adb s-taskin.o yes
compile_ada runtime/core/flyology.ads flyology.o
compile_ada runtime/core/flyology-validation.adb flyology-validation.o
compile_ada runtime/core/flyology-boot_validation.adb flyology-boot_validation.o
compile_ada "arch/$architecture/flyology-architecture_context.ads" \
    flyology-architecture_context.o
compile_ada "arch/$architecture/flyology-m2_architecture.adb" \
    flyology-m2_architecture.o
compile_ada runtime/m3/flyology-m3_runtime.adb flyology-m3_runtime.o generated
compile_ada runtime/m3/s-multip.adb s-multip.o yes
compile_ada runtime/m3/s-tassta.adb s-tassta.o yes
compile_ada runtime/m3/s-soflin.adb s-soflin.o yes
compile_ada runtime/m3/a-taside.adb a-taside.o yes
compile_ada runtime/m3/flyology-m3_demo.adb flyology-m3_demo.o
compile_ada runtime/bootstrap/flyology-binder_support.adb \
    flyology-binder_support.o
compile_ada runtime/m3/flyology_m3.adb flyology_m3.o

scripts/toolchain.sh exec-at "$architecture" "$output_directory" \
    "$target-gnatbind" -nostdinc -nostdlib -n -minimal \
    -I../../../runtime/bootstrap -I../../../runtime/core \
    -I../../../runtime/m3 -I../../../arch/"$architecture" \
    -I. flyology_m3.ali

compile_ada "$output_directory/b~flyology_m3.adb" b~flyology_m3.o generated

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "arch/$architecture/m1_entry.S" -o "$output_directory/m3_entry.o" \
    -DFLYOLOGY_M2 -DFLYOLOGY_M3 -ffreestanding \
    -fno-stack-protector -fno-pic -fno-pie $architecture_flags

for source in context memory limine_requests; do
    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "arch/$architecture/$source.S" \
        -o "$output_directory/$source.o" \
        -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
        $architecture_flags
done

scripts/toolchain.sh exec "$architecture" "$target-ld" \
    --build-id=none --fatal-warnings --gc-sections -z noexecstack \
    -T "arch/$architecture/m1.ld" \
    -o "$output_directory/flyology-m3.elf" \
    "$output_directory/m3_entry.o" \
    "$output_directory/context.o" \
    "$output_directory/memory.o" \
    "$output_directory/limine_requests.o" \
    "$output_directory/b~flyology_m3.o" \
    "$output_directory/flyology_m3.o" \
    "$output_directory/flyology-m3_demo.o" \
    "$output_directory/a-taside.o" \
    "$output_directory/s-soflin.o" \
    "$output_directory/s-tassta.o" \
    "$output_directory/s-multip.o" \
    "$output_directory/flyology-m3_runtime.o" \
    "$output_directory/s-taskin.o" \
    "$output_directory/s-tasinf.o" \
    "$output_directory/s-parame.o" \
    "$output_directory/a-reatim.o" \
    "$output_directory/ada.o" \
    "$output_directory/flyology-m2_architecture.o" \
    "$output_directory/flyology-architecture_context.o" \
    "$output_directory/flyology-binder_support.o" \
    "$output_directory/flyology-boot_validation.o" \
    "$output_directory/flyology-validation.o" \
    "$output_directory/flyology.o" \
    "$output_directory/s-stalib.o" \
    "$output_directory/system.o"

test -z "$(scripts/toolchain.sh exec "$architecture" \
    "$target-nm" -u "$output_directory/flyology-m3.elf")"

FLYOLOGY_DISK_OUTPUT_DIRECTORY="$output_directory" \
    scripts/build-disk.sh "$architecture" \
    "$output_directory/flyology-m3.elf"
