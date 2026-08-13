#!/bin/sh
set -eu

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

mkdir -p build/proof
set +e
proof_output=$(
    "$gnatprove_command" -P proof/flyology_proof.gpr \
        -j0 --level=1 --output=oneline --output-header \
        --warnings=error 2>&1
)
proof_status=$?
set -e

printf '%s\n' "$proof_output" | tee build/proof/gnatprove-run.txt
test "$proof_status" -eq 0 || exit "$proof_status"
printf '%s\n' "$proof_output" | \
    grep -E 'Success: all checks proved \([1-9][0-9]* checks\)'
