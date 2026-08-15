#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/verify-bootstrap-reproducible.sh
scripts/inspect-bootstrap.sh x86_64
scripts/inspect-bootstrap.sh aarch64

scripts/run-bootstrap.sh x86_64 1
scripts/run-bootstrap.sh x86_64 4
scripts/run-bootstrap.sh aarch64 1
scripts/run-bootstrap.sh aarch64 4

FLYOLOGY_BOOT_VARIANT=last-chance scripts/build-bootstrap.sh x86_64
FLYOLOGY_BOOT_VARIANT=last-chance scripts/build-bootstrap.sh aarch64
scripts/run-bootstrap.sh x86_64 1 last-chance
scripts/run-bootstrap.sh aarch64 1 last-chance

echo 'FLYOLOGY:BOOTSTRAP:GATE:PASS'
