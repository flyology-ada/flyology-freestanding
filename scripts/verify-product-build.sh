#!/bin/sh
set -eu

legacy_root=build/product-differential/legacy
product_root=build/product-differential/product

for architecture in x86_64 aarch64; do
    FLYOLOGY_M6_OUTPUT_ROOT="$legacy_root" \
        scripts/build-m6.sh "$architecture" >/dev/null
    FLYOLOGY_PRODUCT_OUTPUT_ROOT="$product_root" \
        scripts/build-product.sh "$architecture" domains >/dev/null

    legacy_directory="$legacy_root/$architecture"
    product_directory="$product_root/domains/$architecture"
    for artifact in elf fat; do
        case "$artifact" in
            elf)
                legacy_file="$legacy_directory/flyology-m3.elf"
                product_file="$product_directory/flyology.elf"
                ;;
            fat)
                legacy_file="$legacy_directory/flyology-$architecture.fat"
                product_file="$product_directory/flyology-$architecture.fat"
                ;;
        esac
        legacy_hash=$(shasum -a 256 "$legacy_file")
        product_hash=$(shasum -a 256 "$product_file")
        test "${legacy_hash%% *}" = "${product_hash%% *}"
    done
    echo "FLYOLOGY:PRODUCT:DIFFERENTIAL:PASS:$architecture:domains"
done

echo 'FLYOLOGY:PRODUCT:GATE:PASS'
