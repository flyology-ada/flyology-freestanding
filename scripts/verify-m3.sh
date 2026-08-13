#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/probe-m3-interface.sh
scripts/verify-m3-reproducible.sh
scripts/build-m3.sh x86_64 >/dev/null
scripts/build-m3.sh aarch64 >/dev/null
scripts/inspect-m3.sh x86_64
scripts/inspect-m3.sh aarch64
scripts/run-m3.sh x86_64 1
scripts/run-m3.sh x86_64 4
scripts/run-m3.sh aarch64 1
scripts/run-m3.sh aarch64 4

echo 'FLYOLOGY:M3:GATE:PASS'
