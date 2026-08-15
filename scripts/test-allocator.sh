#!/bin/sh
set -eu

spark_prefix=${FLYOLOGY_SPARK_PREFIX:-"$HOME/.alire"}
gprbuild="$spark_prefix/libexec/spark/bin/gprbuild"
digest=178ad065fb98e9faff22ce3eec07144eb813cb18b2e65517882cb61b94348f49
timeout_command=${FLYOLOGY_TIMEOUT:-/opt/homebrew/bin/gtimeout}
timeout_digest=96d98cb3adafdd41570802625f7511d7d340cbcd4cb7a7278d5706c282a59c33

test -x "$gprbuild"
printf '%s  %s\n' "$digest" "$gprbuild" | shasum -a 256 -c - >/dev/null
test "$("$gprbuild" --version | sed -n '1p')" = \
    'GPRBUILD 26.2 (2026-06-26) (aarch64-apple-darwin24.6.0)'
test -x "$timeout_command"
printf '%s  %s\n' "$timeout_digest" "$timeout_command" | \
    shasum -a 256 -c - >/dev/null
test "$("$timeout_command" --version | sed -n '1p')" = \
    'timeout (GNU coreutils) 9.11'

rm -rf build/host-allocator
"$gprbuild" -q -P tests/host/allocator_tests.gpr
output=$("$timeout_command" --signal=TERM --kill-after=2s 10s \
    build/host-allocator/bin/allocator_tests)
printf '%s\n' "$output"
test "$output" = 'FLYOLOGY:RTS:ALLOCATOR:PASS'
