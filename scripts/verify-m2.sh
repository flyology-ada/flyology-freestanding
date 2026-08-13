#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/check-m2-layout.sh
scripts/verify-m2-reproducible.sh
scripts/inspect-m2.sh x86_64
scripts/inspect-m2.sh aarch64
scripts/run-m2.sh x86_64 1
scripts/run-m2.sh x86_64 4
scripts/run-m2.sh aarch64 1
scripts/run-m2.sh aarch64 4

echo 'FLYOLOGY:M2:GATE:PASS'
