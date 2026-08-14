#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/test-m3-models.sh
scripts/test-m4-models.sh
scripts/probe-m3-interface.sh
scripts/probe-m4-interface.sh
scripts/check-m2-layout.sh
scripts/verify-m3-reproducible.sh
scripts/build-m3.sh x86_64 >/dev/null
scripts/build-m3.sh aarch64 >/dev/null
scripts/inspect-m3.sh x86_64
scripts/inspect-m3.sh aarch64
scripts/check-m4-unwind.sh x86_64
scripts/check-m4-unwind.sh aarch64
FLYOLOGY_M3_TEST_TAG=m4-gate scripts/run-m3.sh x86_64 1
FLYOLOGY_M3_TEST_TAG=m4-gate scripts/run-m3.sh x86_64 4
FLYOLOGY_M3_TEST_TAG=m4-gate scripts/run-m3.sh aarch64 1
FLYOLOGY_M3_TEST_TAG=m4-gate scripts/run-m3.sh aarch64 4
scripts/stress-m4.sh

echo 'FLYOLOGY:M4:GATE:PASS'
