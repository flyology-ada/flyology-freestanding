#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/check-interrupt-layout.sh
scripts/verify-interrupts-reproducible.sh
scripts/inspect-interrupts.sh x86_64
scripts/inspect-interrupts.sh aarch64
scripts/run-interrupts.sh x86_64 1
scripts/run-interrupts.sh x86_64 4
scripts/run-interrupts.sh aarch64 1
scripts/run-interrupts.sh aarch64 4

echo 'FLYOLOGY:INTERRUPTS:GATE:PASS'
