#!/bin/sh
set -eu

test "$#" -eq 4 || {
    echo "usage: $0 x86_64|aarch64 CPU_COUNT IMAGE STATE_DIRECTORY" >&2
    exit 64
}

architecture=$1
cpu_count=$2
image=$3
state_directory=$4
case "$cpu_count" in
    1|2|3|4) ;;
    *) echo "unsupported CPU count: $cpu_count" >&2; exit 64 ;;
esac

qemu_root=${FLYOLOGY_FREESTANDING_QEMU_ROOT:-/opt/homebrew/Cellar/qemu/10.2.0}
firmware_root="$qemu_root/share/qemu"
bundle_directory=${FLYOLOGY_FREESTANDING_UEFI_BUNDLE_DIRECTORY:-}
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

if test -n "$bundle_directory"; then
    code="$bundle_directory/uefi-code.fd"
    vars_template="$bundle_directory/uefi-vars-template.fd"
fi

for required in "$qemu" "$code" "$vars_template" "$image"; do
    test -f "$required" || {
        echo "missing image input: $required" >&2
        exit 66
    }
done

check_digest() {
    printf '%s  %s\n' "$1" "$2" | shasum -a 256 -c - >/dev/null
}

check_digest "$qemu_digest" "$qemu"
check_digest "$code_digest" "$code"
check_digest "$vars_digest" "$vars_template"
test "$("$qemu" --version | sed -n '1p')" = 'QEMU emulator version 10.2.0'

mkdir -p "$state_directory"
vars="$state_directory/vars.fd"
cp "$vars_template" "$vars"
serial=${FLYOLOGY_FREESTANDING_QEMU_SERIAL:-stdio}
qemu_log=${FLYOLOGY_FREESTANDING_QEMU_LOG:-}
timeout_seconds=${FLYOLOGY_FREESTANDING_QEMU_TIMEOUT_SECONDS:-0}
gui=${FLYOLOGY_FREESTANDING_QEMU_GUI:-0}
case "$gui" in
    0|1) ;;
    *) echo "unsupported GUI setting: $gui" >&2; exit 64 ;;
esac

set -- "$qemu" \
    -machine "$machine" -accel tcg,thread=multi -cpu "$cpu_model" \
    -smp "cpus=$cpu_count,sockets=1,cores=$cpu_count,threads=1" -m 256M \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" \
    -drive "if=pflash,format=raw,unit=1,file=$vars" \
    -drive "if=none,id=bootdisk,format=raw,readonly=on,file=$image" \
    -device virtio-blk-pci,drive=bootdisk,bootindex=1

if test "$gui" = 0; then
    set -- "$@" -display none
fi

set -- "$@" -monitor none -serial "$serial" -no-reboot -no-shutdown

if test "$timeout_seconds" = 0; then
    if test -n "$qemu_log"; then
        exec "$@" >"$qemu_log" 2>&1
    else
        exec "$@"
    fi
fi

timeout_command=${FLYOLOGY_FREESTANDING_TIMEOUT:-/opt/homebrew/bin/gtimeout}
timeout_digest=96d98cb3adafdd41570802625f7511d7d340cbcd4cb7a7278d5706c282a59c33
test -x "$timeout_command"
check_digest "$timeout_digest" "$timeout_command"
test "$("$timeout_command" --version | sed -n '1p')" = \
    'timeout (GNU coreutils) 9.11'

set +e
if test -n "$qemu_log"; then
    "$timeout_command" --signal=TERM --kill-after=2s \
        "${timeout_seconds}s" "$@" >"$qemu_log" 2>&1
else
    "$timeout_command" --signal=TERM --kill-after=2s \
        "${timeout_seconds}s" "$@"
fi
status=$?
set -e
case "$status" in
    0|124|137) ;;
    *) echo "QEMU failed with status $status" >&2; exit "$status" ;;
esac
