#!/bin/sh
set -eu

iterations=${FLYOLOGY_M5_STRESS_ITERATIONS:-5}
case "$iterations" in
    ''|*[!0-9]*) echo "invalid iteration count: $iterations" >&2; exit 64 ;;
esac
test "$iterations" -ge 1

case "$#" in
    0)
        architectures='x86_64 aarch64'
        policies='fifo round_robin'
        ;;
    1)
        case "$1" in
            x86_64|aarch64)
                architectures=$1
                policies='fifo round_robin'
                ;;
            fifo|round_robin)
                architectures='x86_64 aarch64'
                policies=$1
                ;;
            *) echo "unsupported architecture or policy: $1" >&2; exit 64 ;;
        esac
        ;;
    2)
        case "$1" in x86_64|aarch64) architectures=$1 ;;
            *) echo "unsupported architecture: $1" >&2; exit 64 ;;
        esac
        case "$2" in fifo|round_robin) policies=$2 ;;
            *) echo "unsupported policy: $2" >&2; exit 64 ;;
        esac
        ;;
    *) echo "usage: $0 [x86_64|aarch64] [fifo|round_robin]" >&2; exit 64 ;;
esac

for architecture in $architectures; do
    for policy in $policies; do
        iteration=1
        while test "$iteration" -le "$iterations"; do
            FLYOLOGY_M5_TEST_TAG="stress-$iteration" \
                scripts/run-m5.sh "$architecture" 4 "$policy"
            iteration=$((iteration + 1))
        done
    done
done

echo "FLYOLOGY:M5:STRESS:PASS:$iterations"
