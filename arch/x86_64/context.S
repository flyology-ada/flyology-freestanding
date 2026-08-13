/* SPDX-License-Identifier: MIT OR Apache-2.0 */

/*
 * Voluntary SysV context: only ABI-preserved state is captured. The saved
 * stack pointer points at the caller return address, so restoring it resumes
 * as though flyology_context_switch had returned.
 *
 * The exact 80-byte layout is mirrored by flyology-architecture_context.ads.
 */
.section .text, "ax", @progbits
.equ CTX_RBX, 0
.equ CTX_RBP, 8
.equ CTX_R12, 16
.equ CTX_R13, 24
.equ CTX_R14, 32
.equ CTX_R15, 40
.equ CTX_RSP, 48
.equ CTX_RIP, 56
.equ CTX_MXCSR, 64
.equ CTX_X87_CONTROL, 68
.equ CTX_FS_BASE, 72
.equ CTX_SIZE, 80

.global flyology_context_switch
.type flyology_context_switch, @function
flyology_context_switch:
    mov %rbx, CTX_RBX(%rdi)
    mov %rbp, CTX_RBP(%rdi)
    mov %r12, CTX_R12(%rdi)
    mov %r13, CTX_R13(%rdi)
    mov %r14, CTX_R14(%rdi)
    mov %r15, CTX_R15(%rdi)
    lea 8(%rsp), %rax
    mov %rax, CTX_RSP(%rdi)
    mov (%rsp), %rax
    mov %rax, CTX_RIP(%rdi)
    stmxcsr CTX_MXCSR(%rdi)
    fnstcw CTX_X87_CONTROL(%rdi)
    mov $0xc0000100, %ecx
    rdmsr
    shl $32, %rdx
    or %rdx, %rax
    mov %rax, CTX_FS_BASE(%rdi)

    mov CTX_FS_BASE(%rsi), %rax
    mov %rax, %rdx
    shr $32, %rdx
    mov $0xc0000100, %ecx
    wrmsr
    ldmxcsr CTX_MXCSR(%rsi)
    fldcw CTX_X87_CONTROL(%rsi)
    mov CTX_RBX(%rsi), %rbx
    mov CTX_RBP(%rsi), %rbp
    mov CTX_R12(%rsi), %r12
    mov CTX_R13(%rsi), %r13
    mov CTX_R14(%rsi), %r14
    mov CTX_R15(%rsi), %r15
    mov CTX_RSP(%rsi), %rsp
    jmp *CTX_RIP(%rsi)

.global flyology_context_start
.type flyology_context_start, @function
flyology_context_start:
    mov %r12, %rdi
    call flyology_task_start
1:
    ud2
    jmp 1b

.section .text.flyology_dispatcher_context_start, "ax", @progbits
.global flyology_dispatcher_context_start
.type flyology_dispatcher_context_start, @function
flyology_dispatcher_context_start:
    mov %r12, %rdi
    call flyology_dispatcher_start
2:
    ud2
    jmp 2b

.section .rodata.flyology_context_layout, "a", @progbits
.balign 2
.short CTX_SIZE, CTX_RBX, CTX_RBP, CTX_R12, CTX_R13, CTX_R14
.short CTX_R15, CTX_RSP, CTX_RIP, CTX_MXCSR, CTX_X87_CONTROL, CTX_FS_BASE

.section .note.GNU-stack, "", @progbits
