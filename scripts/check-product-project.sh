#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest="$repository/alire.toml"
profiles="$repository/config/profiles.toml"

test -f "$manifest"
test -f "$repository/flyology.gpr"
test -f "$repository/gpr/flyology_primitives.gpr"
test -f "$profiles"

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

echo 'FLYOLOGY:PRODUCT:PROJECT:PASS'
