#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest="$repository/alire.toml"
profiles="$repository/config/profiles.toml"

test -f "$manifest"
test -f "$repository/flyology.gpr"
test -f "$repository/gpr/flyology_primitives.gpr"
test -f "$profiles"
test -f "$repository/tests/target/scenarios/flyology_m3.adb"
test -f "$repository/tests/target/scenarios/flyology-conformance-tasking.adb"
test -f "$repository/tests/target/scenarios/flyology-conformance-observations.adb"

grep -F 'name = "flyology_barebones"' "$manifest" >/dev/null
grep -F 'project-files = ["flyology.gpr"]' "$manifest" >/dev/null
grep -F 'for Project_Files use ("gpr/flyology_primitives.gpr");' \
    "$repository/flyology.gpr" >/dev/null
grep -F 'for Library_Name use "flyology_primitives";' \
    "$repository/gpr/flyology_primitives.gpr" >/dev/null

profile_names=$(awk -F ' *= *' '$1 == "name" {
    gsub(/^"|"$/, "", $2)
    print $2
}' "$profiles")
test "$profile_names" = 'tasking
preemptive-fifo
preemptive-round-robin
domains'

for builder in $(awk -F ' *= *' '$1 == "legacy_builder" {
    gsub(/^"|"$/, "", $2)
    print $2
}' "$profiles" | sort -u); do
    test -x "$repository/$builder"
done

for profile in $profile_names; do
    grep -F "    $profile)" "$repository/scripts/build-product.sh" >/dev/null
done

if find "$repository/runtime" -type f \
    \( -name 'flyology-m*_demo.ads' -o -name 'flyology-m*_demo.adb' \
       -o -name 'flyology_m3.adb' -o -name 'flyology-m6_hook.ads' \
       -o -name 'flyology-m6_hook.adb' \) -print | grep .; then
    echo 'target conformance scenario found under runtime/' >&2
    exit 1
fi

if rg -n '\bDemo_[A-Za-z0-9_]+' "$repository/runtime" >/dev/null; then
    echo 'demo-named test hook found in runtime API' >&2
    exit 1
fi

if rg -n 'Flyology\.(Task_Core|M3_Runtime)' \
    "$repository/runtime" "$repository/src" "$repository/tests" >/dev/null; then
    echo 'milestone task authority name found in current source' >&2
    exit 1
fi

test -f "$repository/src/kernel/flyology-kernel.adb"
test -f "$repository/src/rts/flyology-rts.adb"
test -f "$repository/src/gnarl/s-tassta.adb"
test -f "$repository/src/primitives/flyology-dispatcher_model.adb"
test -f "$repository/src/bootstrap/system.ads"
test -f "$repository/src/abi/exception_runtime.c"
test -f "$repository/src/platform/x86_64/m1_entry.S"
test -f "$repository/src/platform/aarch64/m1_entry.S"
test ! -e "$repository/runtime/m3"
test ! -e "$repository/runtime/core"
test ! -e "$repository/runtime/bootstrap"
test ! -e "$repository/runtime/m4/exception_runtime.c"
test ! -e "$repository/arch"

echo 'FLYOLOGY:PRODUCT:PROJECT:PASS'
