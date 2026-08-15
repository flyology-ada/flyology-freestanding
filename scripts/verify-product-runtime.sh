#!/bin/sh
set -eu

output_root=${FLYOLOGY_PRODUCT_OUTPUT_ROOT:-build/product}

for architecture in x86_64 aarch64; do
    for profile in tasking preemptive-fifo preemptive-round-robin domains; do
        FLYOLOGY_PRODUCT_OUTPUT_ROOT="$output_root" \
            scripts/build-product.sh "$architecture" "$profile" >/dev/null
        for cpu_count in 1 4; do
            FLYOLOGY_PRODUCT_OUTPUT_ROOT="$output_root" \
                scripts/run-product.sh "$architecture" "$cpu_count" "$profile"
        done
    done
done

echo 'FLYOLOGY:PRODUCT:RUNTIME_GATE:PASS'
