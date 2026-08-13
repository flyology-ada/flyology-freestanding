#!/bin/sh
set -eu

test "$#" -eq 2 || {
    echo "usage: $0 x86_64|aarch64 1|4" >&2
    exit 64
}

architecture=$1
cpu_count=$2
case "$cpu_count" in
    1|4) ;;
    *) echo "unsupported CPU count: $cpu_count" >&2; exit 64 ;;
esac

qemu_root=${FLYOLOGY_QEMU_ROOT:-/opt/homebrew/Cellar/qemu/10.2.0}
firmware_root="$qemu_root/share/qemu"
test_tag=${FLYOLOGY_M3_TEST_TAG:-gate}
case "$test_tag" in
    *[!A-Za-z0-9_.-]*) echo "invalid test tag: $test_tag" >&2; exit 64 ;;
esac
test_directory="build/m3/tests/$architecture-smp$cpu_count-$test_tag"
mkdir -p "$test_directory"

case "$architecture" in
    x86_64)
        qemu="$qemu_root/bin/qemu-system-x86_64"
        qemu_digest=f716fea89cb460a085a2553c83f9a22501f2077a41af25c382b805a4cc2844f3
        code="$firmware_root/edk2-x86_64-code.fd"
        code_digest=33090cc07675baa5190d9f1e84bf5176b33bcbfa9bacac522961150cdb6dbb2a
        vars_template="$firmware_root/edk2-i386-vars.fd"
        vars_digest=5d2ac383371b408398accee7ec27c8c09ea5b74a0de0ceea6513388b15be5d1e
        machine=pc-q35-10.2
        cpu_model=max,tsc-frequency=1000000000
        ;;
    aarch64)
        qemu="$qemu_root/bin/qemu-system-aarch64"
        qemu_digest=33f0343582de8f0cf984857fe7e7f374f46a6dad4b7749d86450ede79ed029f3
        code="$firmware_root/edk2-aarch64-code.fd"
        code_digest=47765fe344818cbc464b1c14ae658fb4b854f5c2ceffa982411731eb4865594d
        vars_template="$firmware_root/edk2-arm-vars.fd"
        vars_digest=b3b855c5a80310168051164986855692d1bdb06e67619856177965cd87c6774f
        machine=virt-10.2,gic-version=3,virtualization=off,secure=off,dtb-randomness=off
        cpu_model=max
        ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

image="build/m3/$architecture/flyology-$architecture.fat"
for required in "$qemu" "$code" "$vars_template" "$image"; do
    test -f "$required" || {
        echo "missing M3 input: $required" >&2
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
test "$("$qemu" --version | sed -n '1p')" = 'QEMU emulator version 10.2.0'

vars="$test_directory/vars.fd"
serial_log="$test_directory/serial.log"
qemu_log="$test_directory/qemu.log"
cp "$vars_template" "$vars"
: >"$serial_log"
: >"$qemu_log"

timeout_command=${FLYOLOGY_TIMEOUT:-/opt/homebrew/bin/gtimeout}
timeout_digest=96d98cb3adafdd41570802625f7511d7d340cbcd4cb7a7278d5706c282a59c33
test -x "$timeout_command"
check_digest "$timeout_digest" "$timeout_command"
test "$("$timeout_command" --version | sed -n '1p')" = \
    'timeout (GNU coreutils) 9.11'

set +e
"$timeout_command" --signal=TERM --kill-after=2s 20s "$qemu" \
    -machine "$machine" -accel tcg,thread=multi -cpu "$cpu_model" \
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

test "$(count_marker 'FLYOLOGY:ADA:ELABORATION:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:ADA:MAIN:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M3:ORDINARY_TASKS:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M3:SPECIFIC_CPU:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M3:AUTO_MASTER:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M4:RECLAMATION:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M4:DELAYS:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M4:ABSOLUTE_DELAY:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M4:PROTECTED:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M4:RENDEZVOUS:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M4:DYNAMIC_PRIORITY:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M4:CONDITIONAL_ENTRY:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M4:TIMED_ENTRY:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M4:DYNAMIC_TASK:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M4:SELECTIVE_WAIT:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M4:ABORT:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M3:NESTED_MASTER:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M3:TASK_STACKS:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:M3:BOOT_SUBSTRATE:PASS')" -eq 1
test "$(count_marker 'FLYOLOGY:FAIL:')" -eq 0
test "$(count_marker 'PANIC:')" -eq 0
test "$(count_marker 'FLYOLOGY:CORE:ONLINE:')" -eq "$cpu_count"
if test "$cpu_count" -eq 4; then
    test "$(count_marker 'FLYOLOGY:M3:AUTO_PARALLEL:PASS')" -eq 1
else
    test "$(count_marker 'FLYOLOGY:M3:AUTO_PARALLEL:PASS')" -eq 0
fi

core=0
while test "$core" -lt "$cpu_count"; do
    test "$(count_marker "FLYOLOGY:CORE:ONLINE:$core")" -eq 1
    core=$((core + 1))
done

echo "FLYOLOGY:M3:BOOT_TEST:PASS:$architecture:SMP$cpu_count"
