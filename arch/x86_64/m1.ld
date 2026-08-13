/* SPDX-License-Identifier: MIT OR Apache-2.0 */
OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = 0xffffffff80000000;
    .text : ALIGN(4K) { KEEP(*(.text.entry)) *(.text .text.*) } :text
    .rodata : ALIGN(4K)
    {
        *(.rodata .rodata.*)
        *(.gcc_except_table .gcc_except_table.*)
    } :text
    .eh_frame : ALIGN(8)
    {
        __eh_frame_start = .;
        KEEP(*exception_runtime.o(.eh_frame .eh_frame.*))
        KEEP(*(.eh_frame .eh_frame.*))
        LONG(0)
        __eh_frame_end = .;
    } :text
    .data : ALIGN(4K)
    {
        *(.data .data.*)
        . = ALIGN(8);
        KEEP(*(.limine_requests_start))
        KEEP(*(.limine_requests))
        KEEP(*(.limine_requests_end))
        *(.got .got.*)
    } :data
    .bss (NOLOAD) : ALIGN(4K) { *(COMMON) *(.bss .bss.*) } :data
    /DISCARD/ : { *(.comment) *(.note .note.*) }
}

ASSERT(limine_requests_end_marker - limine_requests_start_marker + 16 == 400,
       "Limine request table must be exactly 400 bytes")
