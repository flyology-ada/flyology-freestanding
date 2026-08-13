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
    . = 1M;
    .text : ALIGN(4K) { KEEP(*(.text.entry)) *(.text .text.*) } :text
    .rodata : ALIGN(4K) { *(.rodata .rodata.*) } :text
    .data : ALIGN(4K) { *(.data .data.*) *(.got .got.*) } :data
    .bss (NOLOAD) : ALIGN(4K) { *(COMMON) *(.bss .bss.*) } :data
    /DISCARD/ : { *(.comment) *(.note .note.*) *(.eh_frame .eh_frame.*) }
}
