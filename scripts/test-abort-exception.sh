#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
native_prefix=${FLYOLOGY_FREESTANDING_NATIVE_GNAT_PREFIX:-"$HOME/.local/share/alire/toolchains/gnat_native_15.3.1_36dc7314"}
compiler="$native_prefix/bin/gcc"
builder="$native_prefix/bin/gnatmake"
binder="$native_prefix/bin/gnatbind"
linker="$native_prefix/bin/gnatlink"
compiler_digest=fa728e60b2dc7e3dff407ab847725d8145f3301615bad70c39ef422c8e8b741d
builder_digest=11a4aadc683258c5683cbb82b630e3cecc71ab6e628e825a1d27edc82faa4df3
binder_digest=ba3cc6aa2820b422b5686bb92d3c0391331f23c5d43a9e324b784b052c95a1bd
linker_digest=64b321899a9e2ba77210a25b2de503cf7858e503a50d029ea55f9772cf0292f3
timeout_command=${FLYOLOGY_FREESTANDING_TIMEOUT:-/opt/homebrew/bin/gtimeout}
timeout_digest=96d98cb3adafdd41570802625f7511d7d340cbcd4cb7a7278d5706c282a59c33
output="$repository/build/host-abort-exception"

for tool_and_digest in "$compiler:$compiler_digest" \
    "$builder:$builder_digest" "$binder:$binder_digest" \
    "$linker:$linker_digest" "$timeout_command:$timeout_digest"; do
    tool=${tool_and_digest%:*}
    digest=${tool_and_digest#*:}
    test -x "$tool"
    printf '%s  %s\n' "$digest" "$tool" | shasum -a 256 -c - >/dev/null
done
test "$("$compiler" --version | sed -n '1p')" = \
    'gcc (GNAT-FSF-builds) 15.3.0'
test "$("$builder" --version | sed -n '1p')" = 'GNATMAKE 15.3.0'
test "$("$binder" --version | sed -n '1p')" = 'GNATBIND 15.3.0'
test "$("$linker" --version | sed -n '1p')" = 'GNATLINK 15.3.0'
test "$("$timeout_command" --version | sed -n '1p')" = \
    'timeout (GNU coreutils) 9.11'

mkdir -p "$output"
for probe in rendezvous protected; do
    name="abort_exception_${probe}_black_box"
    rm -f "$output/$name" "$output/$name.ali" "$output/$name.o" \
          "$output/b~$name.adb" "$output/b~$name.ads" \
          "$output/b~$name.ali" "$output/b~$name.o"
    (
        cd "$output"
        "$builder" -q -O0 -gnat2022 -gnata -gnatwa -gnatwe \
            "$repository/probes/synchronization/$name.adb" -o "$name"
    )
    result=$("$timeout_command" --signal=TERM --kill-after=2s 10s \
        "$output/$name")
    test "$result" = \
        "FLYOLOGY:RTS:ABORT_EXCEPTION_BLACK_BOX:PASS:$(printf '%s' "$probe" | tr '[:lower:]' '[:upper:]')"
    printf '%s\n' "$result"
done

echo 'FLYOLOGY:RTS:ABORT_EXCEPTION_BLACK_BOX:PASS'
