/* SPDX-License-Identifier: MIT OR Apache-2.0 */

.section .text.entry, "ax", @progbits
.global _start
.type _start, @function
_start:
    cli
    lea bootstrap_stack_top(%rip), %rsp
    xor %ebp, %ebp
    call flyology_ada_main
1:
    hlt
    jmp 1b
.size _start, . - _start

.section .bss.stack, "aw", @nobits
.balign 16
bootstrap_stack:
    .skip 65536
bootstrap_stack_top:

.section .note.GNU-stack, "", @progbits
