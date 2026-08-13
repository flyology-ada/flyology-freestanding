#!/bin/sh
set -eu

test "$#" -eq 2 || {
    echo "usage: $0 x86_64|aarch64 KERNEL_ELF" >&2
    exit 64
}

architecture=$1
kernel=$2
test -f "$kernel" || {
    echo "missing kernel: $kernel" >&2
    exit 66
}

case "$architecture" in
    x86_64)
        efi=BOOTX64.EFI
        efi_digest=d257add3b8ca480470c50ba5e55899702f19b10d9b29dc8d4a5db97fc4fb8b19
        ;;
    aarch64)
        efi=BOOTAA64.EFI
        efi_digest=b3510d5a3eae21517f73be939358f720266fe47f95abd249b78664171bd65c0e
        ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

dependency_root=${FLYOLOGY_DEPENDENCIES:-downloads}
limine="$dependency_root/limine-12.5.2"
output_directory=${FLYOLOGY_DISK_OUTPUT_DIRECTORY:-"build/m1/$architecture"}
image="$output_directory/flyology-$architecture.fat"
mtools_root=${FLYOLOGY_MTOOLS_ROOT:-/opt/homebrew/bin}
mtools_digest=e8310ca53ac5f471b7cd8b0b4dacd2ef11a57e399e35d034d1b6899e49dd48a6

test -f "$limine/$efi" || {
    echo "missing pinned Limine; run scripts/fetch-limine.sh" >&2
    exit 69
}
printf '%s  %s\n' "$efi_digest" "$limine/$efi" | \
    shasum -a 256 -c - >/dev/null
for utility in mformat mmd mcopy mdir; do
    test -x "$mtools_root/$utility" || {
        echo "missing pinned mtools utility: $mtools_root/$utility" >&2
        exit 69
    }
    printf '%s  %s\n' "$mtools_digest" "$mtools_root/$utility" | \
        shasum -a 256 -c - >/dev/null
done
test "$("$mtools_root/mformat" -V 2>&1 | sed -n '1p')" = \
    'mformat (GNU mtools) 4.0.49'

mkdir -p "$output_directory"
rm -f "$image"
truncate -s 64m "$image"
"$mtools_root/mformat" -i "$image" -F -N 0x464c5901 -v FLYOLOGY ::
"$mtools_root/mmd" -i "$image" ::/EFI ::/EFI/BOOT
"$mtools_root/mcopy" -i "$image" "$limine/$efi" "::/EFI/BOOT/$efi"
"$mtools_root/mcopy" -i "$image" boot/limine.conf ::/EFI/BOOT/limine.conf
"$mtools_root/mcopy" -i "$image" "$kernel" ::/kernel.elf
"$mtools_root/mdir" -i "$image" ::/EFI/BOOT
"$mtools_root/mdir" -i "$image" ::/
shasum -a 256 "$image"
