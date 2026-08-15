#!/bin/sh
set -eu

scripts/check.sh
scripts/prove.sh
scripts/test-tasking-models.sh
scripts/test-synchronization-models.sh
scripts/test-preemption-policy.sh
scripts/test-domain-model.sh
scripts/test-tla-models.sh

echo 'FLYOLOGY:FORMAL_MODELS:PASS'
