#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest="$repository/alire.toml"
profiles="$repository/config/profiles.toml"

test -f "$manifest"
test -f "$repository/flyology.gpr"
test -f "$repository/gpr/flyology_primitives.gpr"
test -f "$repository/gpr/flyology_image.gpr"
test -f "$repository/gpr/flyology_cross.cgpr"
test -f "$profiles"
test -f "$repository/tests/target/scenarios/flyology_conformance.adb"
test -f "$repository/tests/target/scenarios/flyology-conformance-tasking.adb"
test -f "$repository/tests/target/scenarios/flyology-conformance-observations.adb"
test -x "$repository/scripts/build-image.sh"
test -x "$repository/scripts/inspect-image.sh"
test -x "$repository/scripts/run-product.sh"
test -x "$repository/scripts/verify-product-runtime.sh"

grep -F 'name = "flyology_barebones"' "$manifest" >/dev/null
grep -F 'project-files = ["flyology.gpr"]' "$manifest" >/dev/null
grep -F 'for Project_Files use ("gpr/flyology_primitives.gpr");' \
    "$repository/flyology.gpr" >/dev/null
grep -F 'for Library_Name use "flyology_primitives";' \
    "$repository/gpr/flyology_primitives.gpr" >/dev/null
grep -F 'for Main use' "$repository/gpr/flyology_image.gpr" >/dev/null
grep -F '"flyology_conformance.adb"' \
    "$repository/gpr/flyology_image.gpr" >/dev/null
grep -F '"flyology-validation.adb"' \
    "$repository/gpr/flyology_image.gpr" >/dev/null
grep -F '"flyology-boot_validation.adb"' \
    "$repository/gpr/flyology_image.gpr" >/dev/null
grep -F 'for Driver ("Ada") use Ada_Driver;' \
    "$repository/gpr/flyology_cross.cgpr" >/dev/null

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

for project in $(awk -F ' *= *' '$1 == "image_project" || \
    $1 == "toolchain_config" {
    gsub(/^"|"$/, "", $2)
    print $2
}' "$profiles" | sort -u); do
    test -f "$repository/$project"
done

test "$(awk -F ' *= *' '$1 == "image_project" { print $2 }' \
    "$profiles" | sort -u)" = '"gpr/flyology_image.gpr"'
test "$(awk -F ' *= *' '$1 == "toolchain_config" { print $2 }' \
    "$profiles" | sort -u)" = '"gpr/flyology_cross.cgpr"'

grep -F 'gprbuild -c -p -P gpr/flyology_image.gpr' \
    "$repository/scripts/build-image.sh" >/dev/null
if rg -n 'compile_ada|compile_ada[[:space:]]+src/' \
    "$repository/scripts/build-image.sh" >/dev/null; then
    echo 'shell builder duplicates the Ada project source graph' >&2
    exit 1
fi

for profile in $profile_names; do
    grep -F "    $profile)" "$repository/scripts/build-product.sh" >/dev/null
done

if find "$repository/src" -type f \
    \( -name '*_demo.ads' -o -name '*_demo.adb' \) -print | grep .; then
    echo 'target conformance scenario found under src/' >&2
    exit 1
fi

if rg -n '\bDemo_[A-Za-z0-9_]+' "$repository/src" >/dev/null; then
    echo 'demo-named test hook found in product API' >&2
    exit 1
fi

if rg -n 'Flyology\.(M[0-9]_Architecture|M[0-9]_Configuration|M[0-9]_Hook)' \
    "$repository/src" "$repository/config" "$repository/tests/target" \
    >/dev/null; then
    echo 'numbered-stage product configuration or platform unit found' >&2
    exit 1
fi

if find "$repository" \
    \( -path "$repository/.git" -o -path "$repository/build" \) -prune \
    -o -print | sed "s#^$repository/##" | \
    rg '(^|[/_.-])m[0-9]([/_.-]|$)' >/dev/null; then
    echo 'numbered-stage name found in the maintained filesystem' >&2
    exit 1
fi

if rg -n '^procedure Flyology_M[0-9]' \
    "$repository/tests/target/scenarios" >/dev/null; then
    echo 'numbered-stage conformance main found' >&2
    exit 1
fi

if rg -n 'FLYOLOGY_M[0-9]|flyology_m[0-9]|FLYOLOGY:M[0-9]:|\bm[0-9]_' \
    "$repository/src" "$repository/config" \
    "$repository/tests/target" \
    "$repository/scripts/build-image.sh" \
    "$repository/scripts/build-product.sh" \
    "$repository/scripts/inspect-image.sh" \
    "$repository/scripts/run-image.sh" \
    "$repository/scripts/run-product.sh" >/dev/null; then
    echo 'numbered-stage identifier found in the current product surface' >&2
    exit 1
fi

if git -C "$repository" ls-files -z | xargs -0 rg -n -i \
    '(^|[^[:alnum:]])m[0-9]([^[:digit:]]|$)' >/dev/null; then
    echo 'numbered-stage identifier found in maintained content' >&2
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
test ! -e "$repository/runtime/core"
test ! -e "$repository/runtime/bootstrap"
test ! -e "$repository/arch"
test ! -e "$repository/runtime"
test -f \
    "$repository/tests/legacy/checkpoints/interrupts/flyology_interrupt_checkpoint.adb"
test -f "$repository/config/restrictions/product.adc"
test -f "$repository/config/scheduler/fifo/flyology-scheduler_configuration.ads"
test -f "$repository/config/domains/on/flyology-domain_configuration.ads"

echo 'FLYOLOGY:PRODUCT:PROJECT:PASS'
