#!/bin/sh
set -eu

shell_files=$(find scripts examples -type d -name build -prune -o \
    -type f -name '*.sh' -print | sort)
shell_files="$shell_files
scripts/flyology-build
scripts/flyology-run"
test -n "$shell_files"

# shellcheck disable=SC2086
sh -n $shell_files

if command -v shellcheck >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    shellcheck $shell_files
else
    echo 'CHECK:NOTICE:shellcheck-unavailable'
fi

git diff --check

scripts/check-clean-room.sh
scripts/check-product-project.sh

alire_metadata=$(git ls-files | grep -E \
    '(^|/)alire(\.toml|/[^/]*\.(toml|lock))$' || true)
for metadata in $alire_metadata; do
    if grep -nE '/Users/|/home/|/private/var/folders/|[A-Za-z]:\\' \
        "$metadata"; then
        echo "absolute developer path in tracked Alire metadata: $metadata" >&2
        exit 1
    fi
done
if git ls-files | grep -E '(^|/)alire/(build_hash_inputs|tmp)$'; then
    echo 'generated Alire workspace state is tracked' >&2
    exit 1
fi

if find . \( -path './.git' -o -type d -name build \) -prune -o \
    -type f \( -name '*.o' -o -name '*.ali' -o -name '*.elf' -o \
    -name '*.iso' -o -name '*.img' -o -name '*.fd' \) -print | grep .; then
    echo 'generated artifact found outside ignored build directories' >&2
    exit 1
fi

echo 'FLYOLOGY:CHECK:PASS'
