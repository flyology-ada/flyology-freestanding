#!/bin/sh
set -eu

example=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$example"

exec alr -n exec -- sh -c 'exec "$FLYOLOGY_RUN_TOOL" "$@"' \
    flyology-run "$@"
