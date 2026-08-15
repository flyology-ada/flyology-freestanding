#!/bin/sh
set -eu

test "$#" -eq 1 || {
    echo "usage: $0 x86_64|aarch64" >&2
    exit 64
}

architecture=$1
case "$architecture" in
    x86_64) target=x86_64-elf ;;
    aarch64) target=aarch64-elf ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

image="build/bootstrap-minimum/$architecture/flyology-bootstrap-minimum.elf"
test -f "$image" || {
    echo "missing image: $image" >&2
    exit 1
}

scripts/toolchain.sh exec "$architecture" "$target-readelf" -h -l -S "$image"
scripts/toolchain.sh exec "$architecture" "$target-nm" -u "$image"
scripts/toolchain.sh exec "$architecture" "$target-nm" -n "$image" | \
    grep -E ' (_start|flyology_ada_main)$'
shasum -a 256 "$image"
