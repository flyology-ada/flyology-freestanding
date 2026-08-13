#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/verify-m1-reproducible.sh
scripts/inspect-m1.sh x86_64
scripts/inspect-m1.sh aarch64

scripts/run-m1.sh x86_64 1
scripts/run-m1.sh x86_64 4
scripts/run-m1.sh aarch64 1
scripts/run-m1.sh aarch64 4

FLYOLOGY_M1_VARIANT=last-chance scripts/build-m1.sh x86_64
FLYOLOGY_M1_VARIANT=last-chance scripts/build-m1.sh aarch64
scripts/run-m1.sh x86_64 1 last-chance
scripts/run-m1.sh aarch64 1 last-chance

echo 'FLYOLOGY:M1:GATE:PASS'
