#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest="$repository/alire.toml"
profiles="$repository/config/profiles.toml"

test -f "$manifest"
test -f "$repository/flyology_freestanding.gpr"
test -f "$repository/gpr/flyology_freestanding_primitives.gpr"
test -f "$repository/gpr/flyology_freestanding_image.gpr"
test -f "$repository/gpr/flyology_freestanding_exception_probe.gpr"
test -f "$repository/gpr/flyology_freestanding_cross.cgpr"
test -f "$profiles"
test -f "$repository/tests/target/scenarios/flyology_freestanding_conformance.adb"
test -f "$repository/tests/target/scenarios/flyology_freestanding-conformance-tasking.adb"
test -f "$repository/tests/target/scenarios/flyology_freestanding-conformance-observations.adb"
test -x "$repository/scripts/build-image.sh"
test -x "$repository/scripts/flyology-freestanding-build"
test -x "$repository/scripts/flyology-freestanding-run"
test -x "$repository/scripts/run-uefi-image.sh"
test -x "$repository/scripts/inspect-image.sh"
test -x "$repository/scripts/run-product.sh"
test -x "$repository/scripts/verify-product-runtime.sh"

grep -F -- '--gui)' "$repository/scripts/flyology-freestanding-run" >/dev/null
grep -F 'FLYOLOGY_FREESTANDING_QEMU_GUI="$gui"' \
    "$repository/scripts/flyology-freestanding-run" >/dev/null
grep -F 'if test "$gui" = 0; then' \
    "$repository/scripts/run-uefi-image.sh" >/dev/null
grep -F 'test_observations=${FLYOLOGY_FREESTANDING_TEST_OBSERVATIONS:-0}' \
    "$repository/scripts/flyology-freestanding-build" >/dev/null
grep -F 'test_observations=${FLYOLOGY_FREESTANDING_TEST_OBSERVATIONS:-1}' \
    "$repository/scripts/build-image.sh" >/dev/null
grep -F -- '-DFLYOLOGY_FREESTANDING_TEST_OBSERVATIONS' \
    "$repository/scripts/build-image.sh" >/dev/null

grep -F 'name = "flyology_freestanding"' "$manifest" >/dev/null
grep -F 'project-files = ["flyology_freestanding.gpr"]' "$manifest" >/dev/null
grep -F 'aggregate project Flyology_Freestanding is' \
    "$repository/flyology_freestanding.gpr" >/dev/null
grep -F 'for Project_Files use ("gpr/flyology_freestanding_primitives.gpr");' \
    "$repository/flyology_freestanding.gpr" >/dev/null
grep -F 'for Library_Name use "flyology_freestanding_primitives";' \
    "$repository/gpr/flyology_freestanding_primitives.gpr" >/dev/null

#  This is a hard identity migration.  A compatibility root or old build
#  variable would recreate the collision with the separate Flyology project.
retired_crate=flyology'_barebones'
retired_repository=flyology'-barebones'
retired_title='Flyology ''Barebones'
old_symbol_prefix=flyology'_'
old_variable_prefix=FLYOLOGY'_'
if git -C "$repository" grep -n -E \
    "$retired_crate|$retired_repository|$retired_title" -- . \
    ':(exclude)scripts/check-product-project.sh' \
    ':(exclude)docs/adr/0013-freestanding-identity.md' \
    >/dev/null; then
    echo 'retired Barebones identity found in maintained content' >&2
    exit 1
fi
if git -C "$repository" grep -n -P \
    "${old_symbol_prefix}(?!freestanding)|${old_variable_prefix}(?!FREESTANDING)" -- \
    src config tests scripts gpr proof examples alire.toml \
    ':(exclude)scripts/check-product-project.sh' \
    ':(exclude)scripts/inspect-image.sh' >/dev/null; then
    echo 'unqualified Flyology-owned symbol or build variable found' >&2
    exit 1
fi
if git -C "$repository" grep -n -E \
    '(^|[^[:alnum:]_])Flyology\.' -- src config tests examples docs \
    >/dev/null; then
    echo 'retired Flyology Ada root found in maintained content' >&2
    exit 1
fi
if git -C "$repository" ls-files | \
    rg --pcre2 '(^|/)flyology(?:_|-)(?!freestanding)' >/dev/null; then
    echo 'retired Flyology-prefixed path found in maintained content' >&2
    exit 1
fi
test ! -e "$repository/src/primitives/flyology.ads"
test ! -e "$repository/flyology.gpr"
grep -F 'for Main use' "$repository/gpr/flyology_freestanding_image.gpr" >/dev/null
grep -F '"flyology_freestanding_launcher.adb"' \
    "$repository/gpr/flyology_freestanding_image.gpr" >/dev/null
grep -F 'Application_Directory := external ("FLYOLOGY_FREESTANDING_APPLICATION_DIR");' \
    "$repository/gpr/flyology_freestanding_image.gpr" >/dev/null
if rg -n 'FLYOLOGY_FREESTANDING_SCHEDULER_CONFIG_DIR|Scheduler_Directory' \
    "$repository/gpr/flyology_freestanding_image.gpr" \
    "$repository/scripts/build-image.sh" \
    "$repository/scripts/flyology-freestanding-build" >/dev/null; then
    echo 'consumer build still selects scheduler configuration' >&2
    exit 1
fi
if rg -n -- '--profile|FLYOLOGY_FREESTANDING_PROFILE' \
    "$repository/scripts/flyology-freestanding-build" \
    "$repository/scripts/flyology-freestanding-run" >/dev/null; then
    echo 'consumer tools still expose repository profiles' >&2
    exit 1
fi
grep -F 'Generated_Directory := external ("FLYOLOGY_FREESTANDING_GENERATED_DIR");' \
    "$repository/gpr/flyology_freestanding_image.gpr" >/dev/null
grep -F '"flyology_freestanding-validation.adb"' \
    "$repository/gpr/flyology_freestanding_image.gpr" >/dev/null
grep -F '"flyology_freestanding-boot_validation.adb"' \
    "$repository/gpr/flyology_freestanding_image.gpr" >/dev/null
grep -F 'for Driver ("Ada") use Ada_Driver;' \
    "$repository/gpr/flyology_freestanding_cross.cgpr" >/dev/null
grep -F 'for Main use' \
    "$repository/gpr/flyology_freestanding_exception_probe.gpr" >/dev/null
grep -F 'gprbuild -c -p -P gpr/flyology_freestanding_exception_probe.gpr' \
    "$repository/scripts/build-exception-probe.sh" >/dev/null
if rg -n 'compile_ada' \
    "$repository/scripts/build-exception-probe.sh" >/dev/null; then
    echo 'exception probe shell duplicates its Ada project source graph' >&2
    exit 1
fi

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
    "$profiles" | sort -u)" = '"gpr/flyology_freestanding_image.gpr"'
test "$(awk -F ' *= *' '$1 == "toolchain_config" { print $2 }' \
    "$profiles" | sort -u)" = '"gpr/flyology_freestanding_cross.cgpr"'

grep -F 'gprbuild -c -p -P gpr/flyology_freestanding_image.gpr' \
    "$repository/scripts/build-image.sh" >/dev/null
if rg -n 'compile_ada|compile_ada[[:space:]]+src/' \
    "$repository/scripts/build-image.sh" >/dev/null; then
    echo 'shell builder duplicates the Ada project source graph' >&2
    exit 1
fi

for profile in $profile_names; do
    grep -F "    $profile)" "$repository/scripts/build-product.sh" >/dev/null
done

direct_product_callers=$(rg -l -F 'scripts/build-image.sh' \
    "$repository/scripts" --glob '*.sh' --glob 'flyology-freestanding-build' \
    --glob '!check-product-project.sh' | sort)
test "$direct_product_callers" = "$repository/scripts/build-product.sh
$repository/scripts/flyology-freestanding-build"

if find "$repository/src" -type f \
    \( -name '*_demo.ads' -o -name '*_demo.adb' \) -print | grep .; then
    echo 'target conformance scenario found under src/' >&2
    exit 1
fi

if rg -n '\bDemo_[A-Za-z0-9_]+' "$repository/src" >/dev/null; then
    echo 'demo-named test hook found in product API' >&2
    exit 1
fi

if rg -n 'Flyology_Freestanding\.(M[0-9]_Architecture|M[0-9]_Configuration|M[0-9]_Hook)' \
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

if rg -n '^procedure Flyology_Freestanding_M[0-9]' \
    "$repository/tests/target/scenarios" >/dev/null; then
    echo 'numbered-stage conformance main found' >&2
    exit 1
fi

if rg -n 'FLYOLOGY_FREESTANDING_M[0-9]|flyology_freestanding_m[0-9]|FLYOLOGY:M[0-9]:|\bm[0-9]_' \
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

if git -C "$repository" grep -n -i -E \
    '(^|[^[:alnum:]])m[0-9]([^[:digit:]]|$)' -- . \
    ':(exclude)build/**' >/dev/null; then
    echo 'numbered-stage identifier found in maintained content' >&2
    exit 1
fi

test -f "$repository/src/kernel/flyology_freestanding-kernel.adb"
test -f "$repository/src/rts/flyology_freestanding-rts.adb"
test -f "$repository/src/gnarl/s-tassta.adb"
test -f "$repository/src/primitives/flyology_freestanding-dispatcher_model.adb"
test -f \
    "$repository/src/primitives/flyology_freestanding-scheduling_configuration_model.adb"
test -f "$repository/src/application/flyology_freestanding-scheduling.ads"
test -f "$repository/src/application/flyology_freestanding-scheduling.adb"
test -f "$repository/src/bootstrap/system.ads"
test -f "$repository/src/abi/exception_runtime.c"
test -f "$repository/src/platform/x86_64/entry.S"
test -f "$repository/src/platform/aarch64/entry.S"
test ! -e "$repository/runtime/core"
test ! -e "$repository/runtime/bootstrap"
test ! -e "$repository/arch"
test ! -e "$repository/runtime"
test -f \
    "$repository/tests/platform/interrupts/flyology_freestanding_interrupt_checkpoint.adb"
test ! -e "$repository/tests/legacy"
test ! -e "$repository/scripts/build-domain-image.sh"
test ! -e "$repository/scripts/build-preemption-image.sh"
test ! -e "$repository/scripts/inspect-bootstrap-minimum.sh"
test -f "$repository/config/restrictions/product.adc"
test -f "$repository/config/scheduler/fifo.adc"
test -f "$repository/config/scheduler/round_robin.adc"
test -f "$repository/config/domains/on/flyology_freestanding-domain_configuration.ads"

echo 'FLYOLOGY:PRODUCT:PROJECT:PASS'
