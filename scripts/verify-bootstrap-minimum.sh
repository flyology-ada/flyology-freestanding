#!/bin/sh
set -eu

temporary_directory=$(mktemp -d /tmp/flyology-bootstrap-minimum-verify.XXXXXX)
trap 'rm -rf -- "$temporary_directory"' EXIT HUP INT TERM

verify_architecture() {
    architecture=$1
    case "$architecture" in
        x86_64)
            target=x86_64-elf
            expected_machine="Advanced Micro Devices X86-64"
            expected_entry="0x100000"
            ;;
        aarch64)
            target=aarch64-elf
            expected_machine="AArch64"
            expected_entry="0x40000000"
            ;;
        *) exit 64 ;;
    esac

    primary="build/bootstrap-minimum/$architecture/flyology-bootstrap-minimum.elf"
    reproduction="$temporary_directory/$architecture/flyology-bootstrap-minimum.elf"

    scripts/build-bootstrap-minimum.sh "$architecture"
    scripts/build-bootstrap-minimum.sh "$architecture" "$temporary_directory/$architecture"
    cmp "$primary" "$reproduction"

    header=$(scripts/toolchain.sh exec "$architecture" \
        "$target-readelf" -h "$primary")
    printf '%s\n' "$header" | grep -F "Type:                              EXEC"
    printf '%s\n' "$header" | grep -F "Machine:                           $expected_machine"
    printf '%s\n' "$header" | grep -F "Entry point address:               $expected_entry"

    program_headers=$(scripts/toolchain.sh exec "$architecture" \
        "$target-readelf" -lW "$primary")
    printf '%s\n' "$program_headers" | grep -F ' R E '
    printf '%s\n' "$program_headers" | grep -F ' RW '
    if printf '%s\n' "$program_headers" | grep -F ' RWE '; then
        echo "$architecture image contains an RWX segment" >&2
        exit 1
    fi

    sections=$(scripts/toolchain.sh exec "$architecture" \
        "$target-readelf" -SW "$primary")
    if printf '%s\n' "$sections" | grep -E '\.(interp|dynamic|dynsym|rela?|tdata|tbss)([[:space:]]|$)'; then
        echo "$architecture image contains a forbidden hosted/dynamic section" >&2
        exit 1
    fi

    unresolved=$(scripts/toolchain.sh exec "$architecture" \
        "$target-nm" -u "$primary")
    test -z "$unresolved" || {
        printf '%s\n' "$unresolved" >&2
        exit 1
    }

    symbols=$(scripts/toolchain.sh exec "$architecture" \
        "$target-nm" -n "$primary")
    printf '%s\n' "$symbols" | grep -E ' T _start$'
    printf '%s\n' "$symbols" | grep -E ' T flyology_ada_main$'
    shasum -a 256 "$primary"
}

verify_architecture x86_64
verify_architecture aarch64

echo 'FLYOLOGY:BOOTSTRAP_MINIMUM:PASS'
