#!/bin/sh
set -eu

spark_prefix=${FLYOLOGY_SPARK_PREFIX:-"$HOME/.alire"}
gprbuild="$spark_prefix/libexec/spark/bin/gprbuild"
digest=178ad065fb98e9faff22ce3eec07144eb813cb18b2e65517882cb61b94348f49
test -x "$gprbuild"
printf '%s  %s\n' "$digest" "$gprbuild" | shasum -a 256 -c - >/dev/null
test "$("$gprbuild" --version | sed -n '1p')" = \
    'GPRBUILD 26.2 (2026-06-26) (aarch64-apple-darwin24.6.0)'

rm -rf build/host-m4-model
"$gprbuild" -q -P tests/host/m4_model_tests.gpr
output=$(build/host-m4-model/bin/m4_model_tests)
printf '%s\n' "$output"
test "$output" = \
    'FLYOLOGY:M4:MODEL:PASS:EDGES 27113:HASH 10572371148323389297'
