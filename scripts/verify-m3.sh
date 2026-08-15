#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/test-m3-models.sh
scripts/probe-m3-interface.sh
scripts/probe-m4-interface.sh
scripts/check-m2-layout.sh
scripts/verify-m3-reproducible.sh
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/m3 scripts/build-image.sh x86_64 >/dev/null
FLYOLOGY_IMAGE_OUTPUT_ROOT=build/m3 scripts/build-image.sh aarch64 >/dev/null
scripts/inspect-m3.sh x86_64
scripts/inspect-m3.sh aarch64
scripts/run-m3.sh x86_64 1
scripts/run-m3.sh x86_64 4
scripts/run-m3.sh aarch64 1
scripts/run-m3.sh aarch64 4
scripts/stress-m3.sh

echo 'FLYOLOGY:M3:GATE:PASS'
