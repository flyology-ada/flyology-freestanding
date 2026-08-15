#!/bin/sh
set -eu

test "$#" -ge 2 && test "$#" -le 3 || {
    echo "usage: $0 x86_64|aarch64 1|4 [normal|last-chance]" >&2
    exit 64
}

architecture=$1
cpu_count=$2
mode=${3:-normal}
case "$cpu_count" in
    1|4) ;;
    *) echo "unsupported CPU count: $cpu_count" >&2; exit 64 ;;
esac

case "$mode" in
    normal) build_root=build/m1 ;;
    last-chance)
        test "$cpu_count" -eq 1 || {
            echo "last-chance injection is an SMP1 diagnostic" >&2
            exit 64
        }
        build_root=build/m1-last-chance
        ;;
    *) echo "unsupported M1 test mode: $mode" >&2; exit 64 ;;
esac

qemu_root=${FLYOLOGY_QEMU_ROOT:-/opt/homebrew/Cellar/qemu/10.2.0}
firmware_root="$qemu_root/share/qemu"
test_directory="build/m1/tests/$architecture-smp$cpu_count-$mode"
mkdir -p "$test_directory"

case "$architecture" in
    x86_64)
        target=x86_64-elf
        qemu="$qemu_root/bin/qemu-system-x86_64"
        qemu_digest=f716fea89cb460a085a2553c83f9a22501f2077a41af25c382b805a4cc2844f3
        code="$firmware_root/edk2-x86_64-code.fd"
        code_digest=33090cc07675baa5190d9f1e84bf5176b33bcbfa9bacac522961150cdb6dbb2a
        vars_template="$firmware_root/edk2-i386-vars.fd"
        vars_digest=5d2ac383371b408398accee7ec27c8c09ea5b74a0de0ceea6513388b15be5d1e
        machine=pc-q35-10.2
        image="$build_root/x86_64/flyology-x86_64.fat"
        ;;
    aarch64)
        target=aarch64-elf
        qemu="$qemu_root/bin/qemu-system-aarch64"
        qemu_digest=33f0343582de8f0cf984857fe7e7f374f46a6dad4b7749d86450ede79ed029f3
        code="$firmware_root/edk2-aarch64-code.fd"
        code_digest=47765fe344818cbc464b1c14ae658fb4b854f5c2ceffa982411731eb4865594d
        vars_template="$firmware_root/edk2-arm-vars.fd"
        vars_digest=b3b855c5a80310168051164986855692d1bdb06e67619856177965cd87c6774f
        machine=virt-10.2,gic-version=3,virtualization=off,secure=off,dtb-randomness=off
        image="$build_root/aarch64/flyology-aarch64.fat"
        ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

for required in "$qemu" "$code" "$vars_template" "$image"; do
    test -f "$required" || {
        echo "missing M1 input: $required" >&2
        exit 66
    }
done

check_digest() {
    expected=$1
    path=$2
    printf '%s  %s\n' "$expected" "$path" | shasum -a 256 -c - >/dev/null
}

check_digest "$qemu_digest" "$qemu"
check_digest "$code_digest" "$code"
check_digest "$vars_digest" "$vars_template"
test "$("$qemu" --version | sed -n '1p')" = 'QEMU emulator version 10.2.0' || {
    echo "QEMU version contract failed" >&2
    exit 1
}

vars="$test_directory/vars.fd"
serial_log="$test_directory/serial.log"
qemu_log="$test_directory/qemu.log"
cp "$vars_template" "$vars"
: >"$serial_log"
: >"$qemu_log"

timeout_command=${FLYOLOGY_TIMEOUT:-/opt/homebrew/bin/gtimeout}
timeout_digest=96d98cb3adafdd41570802625f7511d7d340cbcd4cb7a7278d5706c282a59c33
test -x "$timeout_command" || {
    echo "pinned GNU timeout is required: $timeout_command" >&2
    exit 69
}
check_digest "$timeout_digest" "$timeout_command"
test "$("$timeout_command" --version | sed -n '1p')" = \
    'timeout (GNU coreutils) 9.11'

set +e
"$timeout_command" --signal=TERM --kill-after=2s 20s "$qemu" \
    -machine "$machine" -accel tcg,thread=multi -cpu max \
    -smp "cpus=$cpu_count,sockets=1,cores=$cpu_count,threads=1" -m 256M \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" \
    -drive "if=pflash,format=raw,unit=1,file=$vars" \
    -drive "if=none,id=bootdisk,format=raw,readonly=on,file=$image" \
    -device virtio-blk-pci,drive=bootdisk,bootindex=1 \
    -display none -monitor none -serial "file:$serial_log" \
    -no-reboot -no-shutdown >"$qemu_log" 2>&1
qemu_status=$?
set -e

case "$qemu_status" in
    0|124|137) ;;
    *)
        echo "QEMU failed with status $qemu_status" >&2
        tail -n 40 "$qemu_log" >&2
        exit 1
        ;;
esac

count_marker() {
    marker=$1
    grep -aFo "$marker" "$serial_log" | wc -l | tr -d ' '
}

if test "$mode" = last-chance; then
    case "$architecture" in
        x86_64) marker='FLYOLOGY:LAST_CHANCE:X86_64' ;;
        aarch64) marker='FLYOLOGY:LAST_CHANCE:AARCH64' ;;
    esac
    test "$(count_marker "$marker")" -eq 1
    test "$(count_marker 'FLYOLOGY:BOOT:PASS')" -eq 0
    test "$(count_marker 'FLYOLOGY:ADA:MAIN:PASS')" -eq 0
    test "$(count_marker 'FLYOLOGY:FAIL:')" -eq 0
    test "$(count_marker 'PANIC:')" -eq 0
    probe_object="$build_root/$architecture/flyology_last_chance_probe.o"
    probe_undefined=$(scripts/toolchain.sh exec "$architecture" \
        "$target-nm" -u "$probe_object" | awk '{ print $NF }')
    test "$probe_undefined" = '__gnat_rcheck_PE_Explicit_Raise'
    scripts/toolchain.sh exec "$architecture" "$target-nm" \
        "$build_root/$architecture/flyology-m1.elf" | \
        grep -E '[[:space:]]flyology_last_chance_probe$' >/dev/null
else
    test "$(count_marker 'FLYOLOGY:ADA:MAIN:PASS')" -eq 1
    test "$(count_marker 'FLYOLOGY:BOOT:PASS')" -eq 1
    test "$(count_marker 'FLYOLOGY:FAIL:')" -eq 0
    test "$(count_marker 'PANIC:')" -eq 0

    core=0
    while test "$core" -lt "$cpu_count"; do
        test "$(count_marker "FLYOLOGY:CORE:ONLINE:$core")" -eq 1
        core=$((core + 1))
    done
    test "$(count_marker 'FLYOLOGY:CORE:ONLINE:')" -eq "$cpu_count"
fi

echo "FLYOLOGY:BOOT:TEST:PASS:$architecture:SMP$cpu_count:$mode"
