/* SPDX-License-Identifier: MIT OR Apache-2.0 */

.section .text.entry, "ax", %progbits
.global _start
.type _start, %function
_start:
    ldr x0, =bootstrap_stack_top
    mov sp, x0
    mov x29, xzr
    mov x30, xzr
    bl flyology_freestanding_ada_main
1:
    wfi
    b 1b
.size _start, . - _start

.section .bss.stack, "aw", %nobits
.balign 16
bootstrap_stack:
    .skip 65536
bootstrap_stack_top:

.section .note.GNU-stack, "", %progbits
