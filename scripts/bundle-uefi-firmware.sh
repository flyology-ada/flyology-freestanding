#!/bin/sh
set -eu

test "$#" -eq 2 || {
    echo "usage: $0 x86_64|aarch64 OUTPUT_DIRECTORY" >&2
    exit 64
}

architecture=$1
output_directory=$2
qemu_root=${FLYOLOGY_FREESTANDING_QEMU_ROOT:-/opt/homebrew/Cellar/qemu/10.2.0}
firmware_root="$qemu_root/share/qemu"
case "$architecture" in
    x86_64)
        code="$firmware_root/edk2-x86_64-code.fd"
        code_digest=33090cc07675baa5190d9f1e84bf5176b33bcbfa9bacac522961150cdb6dbb2a
        vars="$firmware_root/edk2-i386-vars.fd"
        vars_digest=5d2ac383371b408398accee7ec27c8c09ea5b74a0de0ceea6513388b15be5d1e
        ;;
    aarch64)
        code="$firmware_root/edk2-aarch64-code.fd"
        code_digest=47765fe344818cbc464b1c14ae658fb4b854f5c2ceffa982411731eb4865594d
        vars="$firmware_root/edk2-arm-vars.fd"
        vars_digest=b3b855c5a80310168051164986855692d1bdb06e67619856177965cd87c6774f
        ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

for input in "$code" "$vars"; do
    test -f "$input" || {
        echo "missing pinned TianoCore firmware: $input" >&2
        exit 66
    }
done
printf '%s  %s\n' "$code_digest" "$code" | shasum -a 256 -c - >/dev/null
printf '%s  %s\n' "$vars_digest" "$vars" | shasum -a 256 -c - >/dev/null

mkdir -p "$output_directory"
cp "$code" "$output_directory/uefi-code.fd"
cp "$vars" "$output_directory/uefi-vars-template.fd"
printf '%s  %s\n' "$code_digest" "$output_directory/uefi-code.fd" | \
    shasum -a 256 -c - >/dev/null
printf '%s  %s\n' "$vars_digest" \
    "$output_directory/uefi-vars-template.fd" | shasum -a 256 -c - >/dev/null
echo "FLYOLOGY:UEFI:BUNDLE:PASS:$architecture"
