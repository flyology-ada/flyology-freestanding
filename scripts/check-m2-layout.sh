#!/bin/sh
set -eu

expect_line() {
    expected=$1
    file=$2
    grep -Fqx "$expected" "$file" || {
        echo "missing representation line: $expected" >&2
        exit 1
    }
}

check_architecture() {
    architecture=$1
    case "$architecture" in
        x86_64)
            target=x86_64-elf
            architecture_flags='-mno-red-zone -mcmodel=large'
            expected_machine='  Machine:                           Advanced Micro Devices X86-64'
            expected_layout='80 0 8 16 24 32 40 48 56 64 68 72'
            voluntary_size=640
            voluntary_alignment=16
            frame_size=2048
            frame_alignment=64
            expected_interrupt_layout='256 0 120 128 136 144 152 160 168 176 184 192 200 208 216'
            full_size=34816
            full_alignment=64
            expected_full_layout='4352 0 256 128 144 152 184 192 200'
            ;;
        aarch64)
            target=aarch64-elf
            architecture_flags='-mcmodel=large -mgeneral-regs-only'
            expected_machine='  Machine:                           AArch64'
            expected_layout='192 0 16 32 48 64 80 96 112 128 144 160 176 184'
            voluntary_size=1536
            voluntary_alignment=16
            frame_size=6656
            frame_alignment=16
            expected_interrupt_layout='832 0 248 256 264 272 280 288 296 304 312 320'
            full_size=6656
            full_alignment=16
            expected_full_layout='832 0 248 256 264 288 304 312 320'
            ;;
        *)
            echo "unsupported architecture: $architecture" >&2
            exit 64
            ;;
    esac

    output_directory="build/m2/layout/$architecture"
    mkdir -p "$output_directory"
    rm -f "$output_directory"/*.ali \
          "$output_directory"/*.o \
          "$output_directory"/*.rep \
          "$output_directory"/*.bin

    common_flags="-nostdinc -Iruntime/bootstrap -Isrc/primitives -Iarch/$architecture -I$output_directory -gnato"

    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c runtime/bootstrap/system.ads \
        -o "$output_directory/system.o" \
        $common_flags -gnatg -gnatwa -gnatwe $architecture_flags

    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c src/primitives/flyology.ads \
        -o "$output_directory/flyology.o" \
        $common_flags -gnat2022 -gnatwa -gnatwe $architecture_flags

    # GNAT's generated representation report is an independently compiled
    # view of every Ada record clause used by the assembly ABI.
    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "arch/$architecture/flyology-architecture_context.ads" \
        -o "$output_directory/flyology-architecture_context.o" \
        $common_flags -gnat2022 -gnatwa -gnatwe -gnatR2 \
        $architecture_flags \
        >"$output_directory/voluntary.rep" 2>&1

    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "arch/$architecture/flyology-interrupt_frames.ads" \
        -o "$output_directory/flyology-interrupt_frames.o" \
        $common_flags -gnat2022 -gnatwa -gnatwe -gnatR2 \
        $architecture_flags \
        >"$output_directory/interrupt.rep" 2>&1

    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c src/primitives/flyology-clock_model.adb \
        -o "$output_directory/flyology-clock_model.o" \
        $common_flags -gnat2022 -gnatwa -gnatwe $architecture_flags

    # The architecture package composes the voluntary and complete frame
    # records into the task-owned storage consumed by the transfer assembly.
    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "arch/$architecture/flyology-m2_architecture.adb" \
        -o "$output_directory/flyology-m2_architecture.o" \
        $common_flags -gnat2022 -gnatwa -gnatwe -gnatR2 \
        $architecture_flags \
        >"$output_directory/full-context.rep" 2>&1

    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "arch/$architecture/context.S" \
        -o "$output_directory/context.o" \
        -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
        $architecture_flags

    scripts/toolchain.sh exec "$architecture" "$target-readelf" \
        -h "$output_directory/context.o" \
        >"$output_directory/context-header.txt"
    expect_line "$expected_machine" "$output_directory/context-header.txt"

    unresolved=$(scripts/toolchain.sh exec "$architecture" "$target-nm" \
        -u "$output_directory/context.o" | awk '{print $NF}')
    expected_unresolved='flyology_dispatcher_start
flyology_task_start'
    test "$unresolved" = "$expected_unresolved" || {
        echo "unexpected context unresolved symbols: $unresolved" >&2
        exit 1
    }

    scripts/toolchain.sh exec "$architecture" "$target-objcopy" \
        --dump-section \
        ".rodata.flyology_context_layout=$output_directory/layout.bin" \
        "$output_directory/context.o"
    # Both fixed QEMU targets are little endian. The assembly emits a compact
    # table from the same constants used by its load/store instructions.
    # shellcheck disable=SC2046
    set -- $(od -An -tu2 "$output_directory/layout.bin")
    test "$*" = "$expected_layout" || {
        echo "assembly context layout mismatch: $*" >&2
        exit 1
    }

    scripts/toolchain.sh exec "$architecture" "$target-objcopy" \
        --dump-section \
        ".rodata.flyology_full_context_layout=$output_directory/full-layout.bin" \
        "$output_directory/context.o"
    # shellcheck disable=SC2046
    set -- $(od -An -tu2 "$output_directory/full-layout.bin")
    test "$*" = "$expected_full_layout" || {
        echo "assembly full-context layout mismatch: $*" >&2
        exit 1
    }

    # Compile the production interrupt entry and compare the compact table
    # emitted beside the exact offsets used by its save/restore instructions.
    # shellcheck disable=SC2086
    scripts/toolchain.sh exec "$architecture" "$target-gcc" \
        -c "arch/$architecture/m1_entry.S" \
        -o "$output_directory/interrupt-entry.o" \
        -DFLYOLOGY_M2 -ffreestanding -fno-stack-protector -fno-pic -fno-pie \
        $architecture_flags
    scripts/toolchain.sh exec "$architecture" "$target-objcopy" \
        --dump-section \
        ".rodata.flyology_interrupt_layout=$output_directory/interrupt-layout.bin" \
        "$output_directory/interrupt-entry.o"
    # shellcheck disable=SC2046
    set -- $(od -An -tu2 "$output_directory/interrupt-layout.bin")
    test "$*" = "$expected_interrupt_layout" || {
        echo "assembly interrupt layout mismatch: $*" >&2
        exit 1
    }

    expect_line "for Voluntary_Context'Size use $voluntary_size;" \
        "$output_directory/voluntary.rep"
    expect_line "for Voluntary_Context'Alignment use $voluntary_alignment;" \
        "$output_directory/voluntary.rep"
    expect_line "for Interrupt_Frame'Size use $frame_size;" \
        "$output_directory/interrupt.rep"
    expect_line "for Interrupt_Frame'Alignment use $frame_alignment;" \
        "$output_directory/interrupt.rep"
    expect_line "for Full_Context'Size use $full_size;" \
        "$output_directory/full-context.rep"
    expect_line "for Full_Context'Alignment use $full_alignment;" \
        "$output_directory/full-context.rep"

    case "$architecture" in
        x86_64)
            expect_line '   Stack_Pointer at 48 range  0 .. 63;' \
                "$output_directory/voluntary.rep"
            expect_line '   Fs_Base       at 72 range  0 .. 63;' \
                "$output_directory/voluntary.rep"
            expect_line '   Instruction    at 128 range  0 .. 63;' \
                "$output_directory/interrupt.rep"
            expect_line '   Xsave_Address  at 184 range  0 .. 63;' \
                "$output_directory/interrupt.rep"
            expect_line '   Fault_Address  at 208 range  0 .. 63;' \
                "$output_directory/interrupt.rep"
            expect_line '   Frame          at   0 range  0 .. 2047;' \
                "$output_directory/full-context.rep"
            expect_line '   Extended_State at 256 range  0 .. 32767;' \
                "$output_directory/full-context.rep"
            ;;
        aarch64)
            expect_line '   Stack_Pointer at  96 range  0 .. 63;' \
                "$output_directory/voluntary.rep"
            expect_line '   D8_To_D15     at 112 range  0 .. 511;' \
                "$output_directory/voluntary.rep"
            expect_line '   Exception_Address at 256 range  0 .. 63;' \
                "$output_directory/interrupt.rep"
            expect_line '   Thread_Pointer    at 288 range  0 .. 63;' \
                "$output_directory/interrupt.rep"
            expect_line '   Simd              at 320 range  0 .. 4095;' \
                "$output_directory/interrupt.rep"
            expect_line '   Frame at 0 range  0 .. 6655;' \
                "$output_directory/full-context.rep"
            ;;
    esac

    echo "FLYOLOGY:M2:LAYOUT:$architecture:PASS"
}

check_architecture x86_64
check_architecture aarch64
echo 'FLYOLOGY:M2:LAYOUT:PASS'
