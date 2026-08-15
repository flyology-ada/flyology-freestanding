#!/bin/sh
set -eu

first_root=build/product-reproducible/first
second_root=build/product-reproducible/second

for architecture in x86_64 aarch64; do
    for profile in tasking preemptive-fifo preemptive-round-robin domains; do
        FLYOLOGY_PRODUCT_OUTPUT_ROOT="$first_root" \
            scripts/build-product.sh "$architecture" "$profile" >/dev/null
        FLYOLOGY_PRODUCT_OUTPUT_ROOT="$second_root" \
            scripts/build-product.sh "$architecture" "$profile" >/dev/null

        first_directory="$first_root/$profile/$architecture"
        second_directory="$second_root/$profile/$architecture"
        for artifact in flyology.elf "flyology-$architecture.fat"; do
            first_hash=$(shasum -a 256 "$first_directory/$artifact")
            second_hash=$(shasum -a 256 "$second_directory/$artifact")
            test "${first_hash%% *}" = "${second_hash%% *}"
        done
        echo "FLYOLOGY:PRODUCT:REPRODUCIBLE:PASS:$architecture:$profile"
    done
done

echo 'FLYOLOGY:PRODUCT:GATE:PASS'
