#!/bin/sh
set -eu

version=12.5.2
archive_hash=5e2d6eb86623fcdcd2a873c9eca7dcafccb34182c17779535fe824fd57b688c5
x86_hash=d257add3b8ca480470c50ba5e55899702f19b10d9b29dc8d4a5db97fc4fb8b19
arm_hash=b3510d5a3eae21517f73be939358f720266fe47f95abd249b78664171bd65c0e

dependency_root=${FLYOLOGY_FREESTANDING_DEPENDENCIES:-downloads}
archive="$dependency_root/limine-binary-$version.tar.xz"
destination="$dependency_root/limine-$version"
url="https://github.com/Limine-Bootloader/Limine/releases/download/v$version/limine-binary.tar.xz"

mkdir -p "$dependency_root" "$destination"

if ! test -f "$archive"; then
    partial="$archive.partial"
    rm -f "$partial"
    curl --proto '=https' --tlsv1.2 --fail --location \
        --retry 3 --retry-all-errors --output "$partial" "$url"
    printf '%s  %s\n' "$archive_hash" "$partial" | shasum -a 256 -c -
    mv "$partial" "$archive"
fi

printf '%s  %s\n' "$archive_hash" "$archive" | shasum -a 256 -c -
tar -xJf "$archive" -C "$destination" --strip-components=1 \
    limine-binary/BOOTX64.EFI limine-binary/BOOTAA64.EFI \
    limine-binary/LICENSE
printf '%s  %s\n' "$x86_hash" "$destination/BOOTX64.EFI" | shasum -a 256 -c -
printf '%s  %s\n' "$arm_hash" "$destination/BOOTAA64.EFI" | shasum -a 256 -c -

echo "FLYOLOGY:LIMINE:READY:$destination"
