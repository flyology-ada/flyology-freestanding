#!/bin/sh
set -eu

mkdir -p build
proof_lock=build/.prove.lock
if ! mkdir "$proof_lock" 2>/dev/null; then
    echo "another Flyology proof gate owns $proof_lock" >&2
    exit 75
fi
trap 'rmdir "$proof_lock"' EXIT HUP INT TERM

if test -n "${FLYOLOGY_GNATPROVE:-}"; then
    gnatprove_command=$FLYOLOGY_GNATPROVE
elif command -v gnatprove >/dev/null 2>&1; then
    gnatprove_command=$(command -v gnatprove)
else
    spark_prefix=${FLYOLOGY_SPARK_PREFIX:-"$HOME/.alire"}
    gnatprove_command="$spark_prefix/bin/gnatprove"
    PATH="$spark_prefix/libexec/spark/bin:$PATH"
    export PATH
fi

test -x "$gnatprove_command" || {
    echo "gnatprove not found; set FLYOLOGY_GNATPROVE" >&2
    exit 69
}
gnatprove_digest=1feba230ab840e8adff492d25c5beb231c9a89565fa11fed48c778e625cab900
printf '%s  %s\n' "$gnatprove_digest" "$gnatprove_command" | \
    shasum -a 256 -c - >/dev/null || {
        echo "GNATprove binary digest contract failed" >&2
        exit 1
    }
test "$("$gnatprove_command" --version | sed -n '1p')" = 'FSF 16.1.0' || {
    echo "GNATprove version contract failed" >&2
    exit 1
}

mkdir -p build/proof
rm -rf build/proof/gnatprove
proof_jobs=${FLYOLOGY_PROOF_JOBS:-1}
proof_level=${FLYOLOGY_PROOF_LEVEL:-2}
set +e
proof_output=$(
    "$gnatprove_command" -P proof/flyology_proof.gpr \
        -j"$proof_jobs" --level="$proof_level" --output=oneline --output-header \
        --warnings=error 2>&1
)
proof_status=$?
set -e

printf '%s\n' "$proof_output" | tee build/proof/gnatprove-run.txt
test "$proof_status" -eq 0 || exit "$proof_status"
printf '%s\n' "$proof_output" | \
    grep -E 'Success: all checks proved \([1-9][0-9]* checks\)'
