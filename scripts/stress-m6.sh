#!/bin/sh
set -eu

iterations=${FLYOLOGY_M6_STRESS_ITERATIONS:-5}
case "$iterations" in
    ''|*[!0-9]*) echo "invalid iteration count: $iterations" >&2; exit 64 ;;
esac
test "$iterations" -ge 1

architectures=${1:-'x86_64 aarch64'}
case "$architectures" in
    x86_64|aarch64|'x86_64 aarch64') ;;
    *) echo "unsupported architecture: $architectures" >&2; exit 64 ;;
esac

for architecture in $architectures; do
    iteration=1
    while test "$iteration" -le "$iterations"; do
        FLYOLOGY_M6_TEST_TAG="stress-$iteration" \
            scripts/run-m6.sh "$architecture" 4
        iteration=$((iteration + 1))
    done
done

echo "FLYOLOGY:M6:STRESS:PASS:$iterations"
