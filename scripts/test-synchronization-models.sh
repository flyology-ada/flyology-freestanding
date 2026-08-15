#!/bin/sh
set -eu

spark_prefix=${FLYOLOGY_SPARK_PREFIX:-"$HOME/.alire"}
gprbuild="$spark_prefix/libexec/spark/bin/gprbuild"
digest=178ad065fb98e9faff22ce3eec07144eb813cb18b2e65517882cb61b94348f49
test -x "$gprbuild"
printf '%s  %s\n' "$digest" "$gprbuild" | shasum -a 256 -c - >/dev/null
test "$("$gprbuild" --version | sed -n '1p')" = \
    'GPRBUILD 26.2 (2026-06-26) (aarch64-apple-darwin24.6.0)'

rm -rf build/host-synchronization-model
"$gprbuild" -q -P tests/host/synchronization_model_tests.gpr
output=$(build/host-synchronization-model/bin/synchronization_model_tests)
printf '%s\n' "$output"
test "$output" = \
    'FLYOLOGY:RTS:MODEL:PASS:EDGES 224969:HASH 12736863837444350006'
