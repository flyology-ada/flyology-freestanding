#!/bin/sh
set -eu

scripts/verify-formal-models.sh
scripts/test-allocator.sh
scripts/test-abort-exception.sh
scripts/probe-tasking-interface.sh
scripts/probe-synchronization-interface.sh
scripts/probe-preemption-policy.sh
scripts/probe-domain-interface.sh
scripts/check-interrupt-layout.sh
scripts/verify-domains-reproducible.sh

for architecture in x86_64 aarch64; do
    scripts/build-domain-image.sh "$architecture" >/dev/null
    FLYOLOGY_IMAGE_OUTPUT_ROOT=build/domains \
        scripts/inspect-image.sh "$architecture" domains
    FLYOLOGY_IMAGE_OUTPUT_ROOT=build/domains FLYOLOGY_UNWIND_PROFILE=domains \
        scripts/check-unwind.sh "$architecture"
done

for architecture in x86_64 aarch64; do
    FLYOLOGY_IMAGE_OUTPUT_ROOT=build/domains \
        scripts/run-image.sh "$architecture" 1 domains
    FLYOLOGY_IMAGE_OUTPUT_ROOT=build/domains \
        scripts/run-image.sh "$architecture" 4 domains
done

scripts/stress-domains.sh

echo 'FLYOLOGY:DOMAINS:GATE:PASS'
