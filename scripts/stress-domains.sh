#!/bin/sh
set -eu

iterations=${FLYOLOGY_DOMAIN_STRESS_ITERATIONS:-5}
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
        FLYOLOGY_IMAGE_TEST_TAG="stress-$iteration" \
        FLYOLOGY_IMAGE_OUTPUT_ROOT=build/domains \
            scripts/run-image.sh "$architecture" 4 domains
        iteration=$((iteration + 1))
    done
done

echo "FLYOLOGY:DOMAINS:STRESS:PASS:$iterations"
