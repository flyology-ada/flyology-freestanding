#!/bin/sh
set -eu

iterations=${FLYOLOGY_M4_STRESS_ITERATIONS:-10}
case "$iterations" in
    ''|*[!0-9]*) echo "invalid iteration count: $iterations" >&2; exit 64 ;;
esac
test "$iterations" -ge 1

case "$#" in
    0) architectures='x86_64 aarch64' ;;
    1)
        case "$1" in x86_64|aarch64) architectures=$1 ;;
            *) echo "unsupported architecture: $1" >&2; exit 64 ;;
        esac
        ;;
    *) echo "usage: $0 [x86_64|aarch64]" >&2; exit 64 ;;
esac

for architecture in $architectures; do
    iteration=1
    while test "$iteration" -le "$iterations"; do
        FLYOLOGY_M3_TEST_TAG="m4-stress-$iteration" \
            scripts/run-m3.sh "$architecture" 4
        iteration=$((iteration + 1))
    done
done

echo "FLYOLOGY:M4:STRESS:PASS:$iterations"
