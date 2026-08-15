#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest="$repository/alire.toml"
profiles="$repository/config/profiles.toml"

test -f "$manifest"
test -f "$repository/flyology.gpr"
test -f "$repository/gpr/flyology_primitives.gpr"
test -f "$profiles"
test -f "$repository/tests/target/scenarios/flyology_conformance.adb"
test -f "$repository/tests/target/scenarios/flyology-conformance-tasking.adb"
test -f "$repository/tests/target/scenarios/flyology-conformance-observations.adb"
test -x "$repository/scripts/build-image.sh"
test -x "$repository/scripts/run-product.sh"
test -x "$repository/scripts/verify-product-runtime.sh"

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

for builder in $(awk -F ' *= *' '$1 == "image_builder" {
    gsub(/^"|"$/, "", $2)
    print $2
}' "$profiles" | sort -u); do
    test -x "$repository/$builder"
done

for profile in $profile_names; do
    grep -F "    $profile)" "$repository/scripts/build-product.sh" >/dev/null
done

if find "$repository/src" -type f \
    \( -name 'flyology-m*_demo.ads' -o -name 'flyology-m*_demo.adb' \
       -o -name 'flyology_m3.adb' -o -name 'flyology-m6_hook.ads' \
       -o -name 'flyology-m6_hook.adb' \) -print | grep .; then
    echo 'target conformance scenario found under src/' >&2
    exit 1
fi

if rg -n '\bDemo_[A-Za-z0-9_]+' "$repository/src" >/dev/null; then
    echo 'demo-named test hook found in product API' >&2
    exit 1
fi

if rg -n 'Flyology\.(Task_Core|M3_Runtime)' \
    "$repository/src" "$repository/tests/target" >/dev/null; then
    echo 'milestone task authority name found in current source' >&2
    exit 1
fi

if rg -n 'Flyology\.(M[0-9]_Architecture|M[0-9]_Configuration|M[0-9]_Hook)' \
    "$repository/src" "$repository/config" "$repository/tests/target" \
    >/dev/null; then
    echo 'milestone-named product configuration or platform unit found' >&2
    exit 1
fi

if rg -n '^procedure Flyology_M[0-9]' \
    "$repository/tests/target/scenarios" >/dev/null; then
    echo 'milestone-named conformance main found' >&2
    exit 1
fi

test -f "$repository/src/kernel/flyology-kernel.adb"
test -f "$repository/src/rts/flyology-rts.adb"
test -f "$repository/src/gnarl/s-tassta.adb"
test -f "$repository/src/primitives/flyology-dispatcher_model.adb"
test -f "$repository/src/bootstrap/system.ads"
test -f "$repository/src/abi/exception_runtime.c"
test -f "$repository/src/platform/x86_64/entry.S"
test -f "$repository/src/platform/aarch64/entry.S"
test ! -e "$repository/runtime/m3"
test ! -e "$repository/runtime/core"
test ! -e "$repository/runtime/bootstrap"
test ! -e "$repository/arch"
test ! -e "$repository/runtime/m4"
test ! -e "$repository/runtime/m5"
test ! -e "$repository/runtime/m6"
test ! -e "$repository/runtime"
test -f "$repository/tests/legacy/checkpoints/m2/flyology_m2.adb"
test -f "$repository/config/restrictions/product.adc"
test -f "$repository/config/scheduler/fifo/flyology-scheduler_configuration.ads"
test -f "$repository/config/domains/on/flyology-domain_configuration.ads"

echo 'FLYOLOGY:PRODUCT:PROJECT:PASS'
