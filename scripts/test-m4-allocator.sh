#!/bin/sh
set -eu

native_prefix=${FLYOLOGY_NATIVE_GNAT_PREFIX:-"$HOME/.local/share/alire/toolchains/gnat_native_15.3.1_36dc7314"}
compiler="$native_prefix/bin/gcc"
digest=fa728e60b2dc7e3dff407ab847725d8145f3301615bad70c39ef422c8e8b741d
timeout_command=${FLYOLOGY_TIMEOUT:-/opt/homebrew/bin/gtimeout}
timeout_digest=96d98cb3adafdd41570802625f7511d7d340cbcd4cb7a7278d5706c282a59c33

test -x "$compiler"
printf '%s  %s\n' "$digest" "$compiler" | shasum -a 256 -c - >/dev/null
test "$("$compiler" --version | sed -n '1p')" = \
    'gcc (GNAT-FSF-builds) 15.3.0'
test "$("$compiler" -dumpmachine)" = 'aarch64-apple-darwin24.6.0'
test -x "$timeout_command"
printf '%s  %s\n' "$timeout_digest" "$timeout_command" | \
    shasum -a 256 -c - >/dev/null
test "$("$timeout_command" --version | sed -n '1p')" = \
    'timeout (GNU coreutils) 9.11'

mkdir -p build/host-allocator
"$compiler" -std=c11 -O2 -Wall -Wextra -Werror -pthread \
    -DFLYOLOGY_ALLOCATOR_TEST \
    runtime/m4/allocator_runtime.c tests/host/m4_allocator_tests.c \
    -o build/host-allocator/m4_allocator_tests
output=$("$timeout_command" --signal=TERM --kill-after=2s 10s \
    build/host-allocator/m4_allocator_tests)
printf '%s\n' "$output"
test "$output" = 'FLYOLOGY:M4:ALLOCATOR:PASS'
