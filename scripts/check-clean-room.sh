#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest="$repository/docs/clean-room/interfaces.toml"

test -f "$manifest"

schema_version=$(awk -F ' *= *' '$1 == "schema_version" { print $2 }' "$manifest")
test "$schema_version" = 2

ids=$(awk -F ' *= *' '$1 == "id" { gsub(/^"|"$/, "", $2); print $2 }' "$manifest")
test -n "$ids"
duplicate_ids=$(printf '%s\n' "$ids" | sort | uniq -d)
test -z "$duplicate_ids"

statuses=$(awk -F ' *= *' '$1 == "status" { gsub(/^"|"$/, "", $2); print $2 }' "$manifest")
for status in $statuses; do
    case "$status" in
        supported|bounded|fail_closed|historical) ;;
        *)
            echo "unknown clean-room status: $status" >&2
            exit 1
            ;;
    esac
done

for key in methodology toolchain_lock record probe implementation \
    implementation_inventory gate; do
    awk -F ' *= *' -v key="$key" '$1 == key {
        value = $2
        gsub(/^"|"$/, "", value)
        print value
    }' "$manifest" |
    while IFS= read -r referenced_path; do
        if [ ! -e "$repository/$referenced_path" ]; then
            echo "clean-room manifest $key path does not exist: $referenced_path" >&2
            exit 1
        fi
    done
done

awk -F ' *= *' '$1 == "implementation_inventory" {
    value = $2
    gsub(/^"|"$/, "", value)
    print value
}' "$manifest" |
while IFS= read -r inventory_path; do
    test -n "$inventory_path"
    while IFS= read -r implementation_path; do
        case "$implementation_path" in
            ''|'#'*) continue ;;
        esac
        if [ ! -f "$repository/$implementation_path" ]; then
            echo "clean-room implementation path does not exist: $implementation_path" >&2
            exit 1
        fi
        if ! git -C "$repository" ls-files --error-unmatch \
            "$implementation_path" >/dev/null 2>&1; then
            echo "clean-room implementation path is not tracked: $implementation_path" >&2
            exit 1
        fi
    done < "$repository/$inventory_path"
done

expected_fields='id compiler architectures record probe implementation implementation_inventory gate status claims proof_scope'
awk -v expected="$expected_fields" '
    function fail(message) {
        print message > "/dev/stderr"
        exit 1
    }
    /^\[\[interface_set\]\]$/ {
        if (seen_set) {
            for (field_index = 1; field_index <= field_count; field_index++)
                if (!present[fields[field_index]])
                    fail("interface_set " identifier " lacks " fields[field_index])
        }
        delete present
        field_count = split(expected, fields, " ")
        seen_set = 1
        identifier = "<unknown>"
        next
    }
    seen_set && /^[a-z_]+ *=/ {
        name = $1
        sub(/ *$/, "", name)
        present[name] = 1
        if (name == "id") {
            identifier = $0
            sub(/^[^=]*= *"/, "", identifier)
            sub(/".*$/, "", identifier)
        }
    }
    END {
        if (!seen_set)
            fail("clean-room manifest contains no interface_set")
        for (field_index = 1; field_index <= field_count; field_index++)
            if (!present[fields[field_index]])
                fail("interface_set " identifier " lacks " fields[field_index])
    }
' "$manifest"

echo 'FLYOLOGY:CLEAN_ROOM:PASS'
