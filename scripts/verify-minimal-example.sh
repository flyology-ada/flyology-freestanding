#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
example="$repository/examples/minimal"
repro_root="$example/build/repro"

alr -n -C "$example" build
test -f "$example/alire/build_hash_inputs"
if grep -nE '/Users/|/home/|/private/var/folders/|[A-Za-z]:\\' \
    "$example/alire/build_hash_inputs"; then
    echo 'absolute developer path in generated example build inputs' >&2
    exit 1
fi
FLYOLOGY_OUTPUT_ROOT="$repro_root" \
    alr -n -C "$example" exec -- sh -c \
    'exec "$FLYOLOGY_BUILD_TOOL"' flyology-build

check_digest() {
    expected=$1
    path=$2
    printf '%s  %s\n' "$expected" "$path" | shasum -a 256 -c - >/dev/null
}

for architecture in x86_64 aarch64; do
    primary="$example/build/$architecture"
    secondary="$repro_root/$architecture"
    for name in flyology.elf "flyology-$architecture.fat" \
        uefi-code.fd uefi-vars-template.fd; do
        test -f "$primary/$name"
        test -f "$secondary/$name"
        primary_hash=$(shasum -a 256 "$primary/$name" | awk '{print $1}')
        secondary_hash=$(shasum -a 256 "$secondary/$name" | awk '{print $1}')
        test "$primary_hash" = "$secondary_hash"
    done

    case "$architecture" in
        x86_64)
            code_digest=33090cc07675baa5190d9f1e84bf5176b33bcbfa9bacac522961150cdb6dbb2a
            vars_digest=5d2ac383371b408398accee7ec27c8c09ea5b74a0de0ceea6513388b15be5d1e
            ;;
        aarch64)
            code_digest=47765fe344818cbc464b1c14ae658fb4b854f5c2ceffa982411731eb4865594d
            vars_digest=b3b855c5a80310168051164986855692d1bdb06e67619856177965cd87c6774f
            ;;
    esac
    check_digest "$code_digest" "$primary/uefi-code.fd"
    check_digest "$vars_digest" "$primary/uefi-vars-template.fd"

    test_root="$example/build/tests/$architecture"
    mkdir -p "$test_root"
    serial="$test_root/serial.log"
    qemu="$test_root/qemu.log"
    : >"$serial"
    : >"$qemu"
    FLYOLOGY_QEMU_SERIAL="file:$serial" \
    FLYOLOGY_QEMU_LOG="$qemu" \
        "$example/run.sh" --cpus 4 --timeout 12 "$architecture"

    normalized="$test_root/serial.normalized"
    tr -d '\r' <"$serial" >"$normalized"
    test "$(grep -aFxc 'OK' "$normalized")" -eq 1
    test "$(grep -aEc '^CORE [1-4] WORKER [12]$' "$normalized")" -eq 8
    for core in 1 2 3 4; do
        for worker in 1 2; do
            test "$(grep -aFxc "CORE $core WORKER $worker" "$normalized")" -eq 1
        done
    done
    test "$(grep -aFc 'FLYOLOGY:ADA:MAIN:PASS' "$serial")" -eq 1
    test "$(grep -aFc 'FLYOLOGY:TASKING:BOOT_SUBSTRATE:PASS' "$serial")" -eq 1
    test "$(grep -aFc 'FLYOLOGY:FAIL:' "$serial")" -eq 0
    test "$(grep -aFc 'PANIC:' "$serial")" -eq 0
    awk '
        { sub(/\r$/, "") }
        $0 == "OK" { ok = NR }
        $0 == "FLYOLOGY:ADA:MAIN:PASS" { main = NR }
        END { exit !(ok > 0 && main > ok) }
    ' "$normalized"
    echo "FLYOLOGY:EXAMPLE:MINIMAL:PASS:$architecture"
done

echo 'FLYOLOGY:EXAMPLE:MINIMAL:GATE:PASS'
