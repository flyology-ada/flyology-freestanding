#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/test-m3-models.sh
scripts/test-m4-models.sh
scripts/test-m5-policy.sh
scripts/test-tla-models.sh

echo 'FLYOLOGY:FORMAL_MODELS:PASS'
