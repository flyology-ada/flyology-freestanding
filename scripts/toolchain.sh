#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)

usage() {
    echo "usage: $0 install|exec ARCH [COMMAND ...]" >&2
    exit 64
}

test "$#" -ge 2 || usage
operation=$1
architecture=$2
shift 2

case "$architecture" in
    x86_64)
        compiler="gnat_x86_64_elf=15.3.1"
        workspace="$repository_root/toolchains/x86_64"
        ;;
    aarch64)
        compiler="gnat_aarch64_elf=15.3.1"
        workspace="$repository_root/toolchains/aarch64"
        ;;
    *)
        echo "unsupported architecture: $architecture" >&2
        exit 64
        ;;
esac

case "$operation" in
    install)
        test "$#" -eq 0 || usage
        exec alr -n -C "$workspace" toolchain --select --local \
            "$compiler" "gprbuild=26.0.1"
        ;;
    exec)
        test "$#" -gt 0 || usage
        exec alr -C "$workspace" exec -- \
            sh -c 'cd "$1" && shift && exec "$@"' sh "$repository_root" "$@"
        ;;
    *)
        usage
        ;;
esac
