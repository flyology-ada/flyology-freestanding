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

output_root=${FLYOLOGY_M3_OUTPUT_ROOT:-build/m3}
output_directory="$output_root/$architecture"
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
compile_ada runtime/m3/a-calend.ads a-calend.o yes
compile_ada runtime/m3/a-caldel.adb a-caldel.o yes
compile_ada runtime/m3/a-reatim.adb a-reatim.o yes
compile_ada runtime/m3/a-retide.adb a-retide.o yes
compile_ada runtime/m3/a-except.adb a-except.o yes
compile_ada runtime/m3/s-parame.ads s-parame.o yes
compile_ada runtime/m3/s-tasinf.ads s-tasinf.o yes
compile_ada runtime/m3/s-taskin.adb s-taskin.o yes
compile_ada runtime/m3/s-finpri.adb s-finpri.o yes
compile_ada runtime/m3/s-taprob.adb s-taprob.o yes
compile_ada runtime/m3/s-tasren.adb s-tasren.o yes
compile_ada runtime/core/flyology.ads flyology.o
compile_ada runtime/core/flyology-validation.adb flyology-validation.o
compile_ada runtime/core/flyology-boot_validation.adb flyology-boot_validation.o
compile_ada runtime/core/flyology-dispatcher_model.adb \
    flyology-dispatcher_model.o
compile_ada runtime/core/flyology-placement_model.adb flyology-placement_model.o
compile_ada runtime/core/flyology-task_primitives_contract.ads \
    flyology-task_primitives_contract.o
compile_ada runtime/core/flyology-clock_model.adb flyology-clock_model.o
compile_ada runtime/core/flyology-timer_model.adb flyology-timer_model.o
compile_ada runtime/core/flyology-ceiling_model.adb flyology-ceiling_model.o
compile_ada runtime/core/flyology-priority_queue_model.adb \
    flyology-priority_queue_model.o
compile_ada runtime/core/flyology-wait_arbitration_model.adb \
    flyology-wait_arbitration_model.o
compile_ada "arch/$architecture/flyology-architecture_context.ads" \
    flyology-architecture_context.o
compile_ada "arch/$architecture/flyology-m2_architecture.adb" \
    flyology-m2_architecture.o
compile_ada runtime/core/flyology-task_core.adb flyology-task_core.o generated
compile_ada runtime/m3/flyology-m3_runtime.adb flyology-m3_runtime.o generated
compile_ada runtime/m3/s-multip.adb s-multip.o yes
compile_ada runtime/m3/s-tassta.adb s-tassta.o yes
compile_ada runtime/m3/s-soflin.adb s-soflin.o yes
compile_ada runtime/m3/a-taside.adb a-taside.o yes
compile_ada runtime/m3/a-taidco.adb a-taidco.o yes
compile_ada runtime/m3/a-dynpri.adb a-dynpri.o yes
compile_ada runtime/m3/flyology-m3_demo.adb flyology-m3_demo.o
compile_ada runtime/bootstrap/flyology-binder_support.adb \
    flyology-binder_support.o
compile_ada runtime/m3/flyology_m3.adb flyology_m3.o

scripts/toolchain.sh exec-at "$architecture" "$output_directory" \
    "$target-gnatbind" -nostdinc -nostdlib -n -minimal \
    -I"$repository/runtime/bootstrap" -I"$repository/runtime/core" \
    -I"$repository/runtime/m3" -I"$repository/arch/$architecture" \
    -I. flyology_m3.ali

compile_ada "$output_directory/b~flyology_m3.adb" b~flyology_m3.o generated

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c "arch/$architecture/m1_entry.S" -o "$output_directory/m3_entry.o" \
    -DFLYOLOGY_M2 -DFLYOLOGY_M3 -DFLYOLOGY_EXCEPTION -ffreestanding \
    -fno-stack-protector -fno-pic -fno-pie $architecture_flags

for source in context memory limine_requests; do
    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "arch/$architecture/$source.S" \
        -o "$output_directory/$source.o" \
        -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
        $architecture_flags
done

# shellcheck disable=SC2086
scripts/toolchain.sh exec "$architecture" "$target-gcc" \
    -c runtime/m4/exception_runtime.c \
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
    -T "arch/$architecture/m1.ld" \
    -o "$output_directory/flyology-m3.elf" \
    "$output_directory/m3_entry.o" \
    "$output_directory/context.o" \
    "$output_directory/memory.o" \
    "$output_directory/limine_requests.o" \
    "$output_directory/exception_runtime.o" \
    "$output_directory/b~flyology_m3.o" \
    "$output_directory/flyology_m3.o" \
    "$output_directory/flyology-m3_demo.o" \
    "$output_directory/a-taside.o" \
    "$output_directory/a-taidco.o" \
    "$output_directory/a-dynpri.o" \
    "$output_directory/s-soflin.o" \
    "$output_directory/s-tassta.o" \
    "$output_directory/s-multip.o" \
    "$output_directory/flyology-m3_runtime.o" \
    "$output_directory/flyology-task_core.o" \
    "$output_directory/flyology-placement_model.o" \
    "$output_directory/flyology-task_primitives_contract.o" \
    "$output_directory/flyology-clock_model.o" \
    "$output_directory/flyology-timer_model.o" \
    "$output_directory/flyology-ceiling_model.o" \
    "$output_directory/flyology-priority_queue_model.o" \
    "$output_directory/flyology-wait_arbitration_model.o" \
    "$output_directory/flyology-dispatcher_model.o" \
    "$output_directory/s-taskin.o" \
    "$output_directory/s-taprob.o" \
    "$output_directory/s-tasren.o" \
    "$output_directory/s-finpri.o" \
    "$output_directory/s-tasinf.o" \
    "$output_directory/s-parame.o" \
    "$output_directory/a-reatim.o" \
    "$output_directory/a-retide.o" \
    "$output_directory/a-caldel.o" \
    "$output_directory/a-calend.o" \
    "$output_directory/ada.o" \
    "$output_directory/a-except.o" \
    "$output_directory/flyology-m2_architecture.o" \
    "$output_directory/flyology-architecture_context.o" \
    "$output_directory/flyology-binder_support.o" \
    "$output_directory/flyology-boot_validation.o" \
    "$output_directory/flyology-validation.o" \
    "$output_directory/flyology.o" \
    "$output_directory/s-stalib.o" \
    "$output_directory/system.o" \
    --start-group "$libgcc" --end-group

test -z "$(scripts/toolchain.sh exec "$architecture" \
    "$target-nm" -u "$output_directory/flyology-m3.elf")"

FLYOLOGY_DISK_OUTPUT_DIRECTORY="$output_directory" \
    scripts/build-disk.sh "$architecture" \
    "$output_directory/flyology-m3.elf"
