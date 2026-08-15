#!/bin/sh
set -eu

test "$#" -eq 1 || {
    echo "usage: $0 x86_64|aarch64" >&2
    exit 64
}

architecture=$1
case "$architecture" in
    x86_64)
        target=x86_64-elf
        machine='Advanced Micro Devices X86-64'
        ;;
    aarch64)
        target=aarch64-elf
        machine='AArch64'
        ;;
    *) echo "unsupported architecture: $architecture" >&2; exit 64 ;;
esac

elf="build/bootstrap/$architecture/flyology_freestanding-bootstrap.elf"
test -f "$elf" || {
    echo "missing bootstrap ELF: $elf" >&2
    exit 66
}

readelf_output=$(scripts/toolchain.sh exec "$architecture" "$target-readelf" -h -l -S -r "$elf")
program_output=$(scripts/toolchain.sh exec "$architecture" "$target-readelf" -l "$elf")
nm_output=$(scripts/toolchain.sh exec "$architecture" "$target-nm" -n "$elf")

printf '%s\n' "$readelf_output" | grep -F 'Class:                             ELF64' >/dev/null
printf '%s\n' "$readelf_output" | grep -F 'Type:                              EXEC (Executable file)' >/dev/null
printf '%s\n' "$readelf_output" | grep -F "Machine:                           $machine" >/dev/null
printf '%s\n' "$readelf_output" | grep -F 'Entry point address:               0xffffffff80000000' >/dev/null
printf '%s\n' "$readelf_output" | grep -F 'There are no relocations in this file.' >/dev/null

if printf '%s\n' "$program_output" | grep -E 'INTERP|DYNAMIC|TLS|RWE' >/dev/null; then
    echo "forbidden hosted, TLS, dynamic, or RWX ELF state" >&2
    exit 1
fi

for symbol in _start adainit _ada_flyology_freestanding_boot_checkpoint \
    __gnat_last_chance_handler flyology_freestanding_memory_entry_is_valid \
    flyology_freestanding_memory_entries_are_disjoint \
    flyology_freestanding_topology_identities_are_distinct \
    limine_base_revision limine_stack_size_request limine_hhdm_request \
    limine_paging_mode_request limine_memmap_request \
    limine_executable_address_request limine_mp_request; do
    printf '%s\n' "$nm_output" | grep -E "[[:space:]]$symbol$" >/dev/null
done

if test "$architecture" = aarch64; then
    printf '%s\n' "$nm_output" | \
        grep -E '[[:space:]]flyology_freestanding_executable_translation_is_valid$' >/dev/null
fi

test -z "$(scripts/toolchain.sh exec "$architecture" "$target-nm" -u "$elf")"

symbol_low_address() {
    symbol=$1
    address=$(printf '%s\n' "$nm_output" | awk -v wanted="$symbol" '$3 == wanted { print $1 }')
    test -n "$address"
    printf '%s\n' "$address" | sed 's/.*\(.\{8\}\)$/\1/'
}

begin=$(symbol_low_address limine_requests_start_marker)
end=$(symbol_low_address limine_requests_end_marker)
test "$((0x$end - 0x$begin + 16))" -eq 400

check_offset() {
    symbol=$1
    expected=$2
    actual=$(symbol_low_address "$symbol")
    test "$((0x$actual - 0x$begin))" -eq "$expected"
}

check_offset limine_requests_start_marker 0
check_offset limine_base_revision 32
check_offset limine_stack_size_request 56
check_offset limine_hhdm_request 112
check_offset limine_paging_mode_request 160
check_offset limine_memmap_request 232
check_offset limine_executable_address_request 280
check_offset limine_mp_request 328
check_offset limine_requests_end_marker 384

request_binary="build/bootstrap/$architecture/limine-requests.bin"
scripts/toolchain.sh exec "$architecture" "$target-objcopy" \
    --dump-section ".data=$request_binary" "$elf"
data_address=$(scripts/toolchain.sh exec "$architecture" "$target-readelf" -SW "$elf" | \
    awk '$3 == ".data" { print $5 }')
test -n "$data_address"
request_address=$(symbol_low_address limine_requests_start_marker)
request_offset=$((0x$request_address - 0x$(printf '%s' "$data_address" | sed 's/.*\(.\{8\}\)$/\1/')))

expect_u64() {
    relative=$1
    expected=$2
    actual=$(od -An -tu8 -N8 -j $((request_offset + relative)) "$request_binary" | tr -d ' ')
    test "$actual" = "$expected"
}

# Markers, base tag/revision, common magic, request IDs, revisions, response
# slots, stack size, paging bounds, and architecture-specific MP flags.
expect_u64 0 17778228581330571694
expect_u64 8 18066500419537648079
expect_u64 16 8672928822407193366
expect_u64 24 1737987079877605849
expect_u64 32 17966595237268006600
expect_u64 40 7672788277485857756
expect_u64 48 6
expect_u64 56 14389525486399949704
expect_u64 64 757423339400917115
expect_u64 72 2472177429088471334
expect_u64 80 16270115406302603837
expect_u64 88 0
expect_u64 96 0
expect_u64 104 65536
expect_u64 112 14389525486399949704
expect_u64 120 757423339400917115
expect_u64 128 5250337122116876370
expect_u64 136 7176572410665641035
expect_u64 144 0
expect_u64 152 0
expect_u64 160 14389525486399949704
expect_u64 168 757423339400917115
expect_u64 176 10791083124793623755
expect_u64 184 11882126634389031050
expect_u64 192 1
expect_u64 200 0
expect_u64 208 0
expect_u64 216 0
expect_u64 224 0
expect_u64 232 14389525486399949704
expect_u64 240 757423339400917115
expect_u64 248 7480265251536666735
expect_u64 256 16358389823600082018
expect_u64 264 0
expect_u64 272 0
expect_u64 280 14389525486399949704
expect_u64 288 757423339400917115
expect_u64 296 8194992790871301987
expect_u64 304 12854480912826934407
expect_u64 312 0
expect_u64 320 0
expect_u64 328 14389525486399949704
expect_u64 336 757423339400917115
expect_u64 344 10783442154351723902
expect_u64 352 11580473669266863072
expect_u64 360 0
expect_u64 368 0
case "$architecture" in
    x86_64) expect_u64 376 1 ;;
    aarch64) expect_u64 376 0 ;;
esac
expect_u64 384 12520253611641474307
expect_u64 392 10768793488028224610

echo "FLYOLOGY:BOOT:INSPECT:PASS:$architecture"
