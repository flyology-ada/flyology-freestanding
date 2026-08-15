/* SPDX-License-Identifier: MIT OR Apache-2.0 */

/* Original freestanding implementations of compiler-emitted C memory ABI. */
.section .text, "ax", @progbits
.global memcpy
.type memcpy, @function
memcpy:
    mov %rdi, %rax
    test %rdx, %rdx
    jz 2f
1:
    movb (%rsi), %cl
    movb %cl, (%rdi)
    inc %rsi
    inc %rdi
    dec %rdx
    jnz 1b
2:
    ret

.global memset
.type memset, @function
memset:
    mov %rdi, %rax
    test %rdx, %rdx
    jz 2f
1:
    movb %sil, (%rdi)
    inc %rdi
    dec %rdx
    jnz 1b
2:
    ret

.section .note.GNU-stack, "", @progbits
