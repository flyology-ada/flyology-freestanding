#!/bin/sh
set -eu

iterations=${FLYOLOGY_FREESTANDING_TASKING_STRESS_ITERATIONS:-3}
product_root=${FLYOLOGY_FREESTANDING_PRODUCT_OUTPUT_ROOT:-build/product}
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
        FLYOLOGY_FREESTANDING_IMAGE_TEST_TAG="stress-$iteration" \
        FLYOLOGY_FREESTANDING_IMAGE_OUTPUT_ROOT="$product_root/tasking" \
            scripts/run-image.sh "$architecture" 4 tasking
        iteration=$((iteration + 1))
    done
done

echo "FLYOLOGY:TASKING:STRESS:PASS:$iterations"
