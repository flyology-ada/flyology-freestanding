/* SPDX-License-Identifier: MIT OR Apache-2.0 */

/*
 * Voluntary SysV context: only ABI-preserved state is captured. The saved
 * stack pointer points at the caller return address, so restoring it resumes
 * as though flyology_freestanding_context_switch had returned.
 *
 * The exact 80-byte layout is mirrored by flyology_freestanding-architecture_context.ads.
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

.equ FULL_R15, 0
.equ FULL_R14, 8
.equ FULL_R13, 16
.equ FULL_R12, 24
.equ FULL_R11, 32
.equ FULL_R10, 40
.equ FULL_R9, 48
.equ FULL_R8, 56
.equ FULL_RBP, 64
.equ FULL_RDI, 72
.equ FULL_RSI, 80
.equ FULL_RDX, 88
.equ FULL_RCX, 96
.equ FULL_RBX, 104
.equ FULL_RAX, 112
.equ FULL_FS_BASE, 120
.equ FULL_RIP, 128
.equ FULL_CS, 136
.equ FULL_RFLAGS, 144
.equ FULL_RSP, 152
.equ FULL_SS, 160
.equ FULL_XSAVE_ADDRESS, 184
.equ FULL_XSAVE_BYTES, 192
.equ FULL_XSAVE_FEATURES, 200
.equ FULL_FRAME_SIZE, 256
.equ FULL_XSAVE, 256
.equ FULL_XSAVE_CAPACITY, 4096
.equ FULL_CONTEXT_SIZE, 4352

.macro save_voluntary base
    mov %rbx, CTX_RBX(\base)
    mov %rbp, CTX_RBP(\base)
    mov %r12, CTX_R12(\base)
    mov %r13, CTX_R13(\base)
    mov %r14, CTX_R14(\base)
    mov %r15, CTX_R15(\base)
    lea 8(%rsp), %rax
    mov %rax, CTX_RSP(\base)
    mov (%rsp), %rax
    mov %rax, CTX_RIP(\base)
    stmxcsr CTX_MXCSR(\base)
    fnstcw CTX_X87_CONTROL(\base)
    mov $0xc0000100, %ecx
    rdmsr
    shl $32, %rdx
    or %rdx, %rax
    mov %rax, CTX_FS_BASE(\base)
.endm

.macro restore_voluntary base, enable_dispatch=0
    mov CTX_FS_BASE(\base), %rax
    mov %rax, %rdx
    shr $32, %rdx
    mov $0xc0000100, %ecx
    wrmsr
    ldmxcsr CTX_MXCSR(\base)
    fldcw CTX_X87_CONTROL(\base)
    mov CTX_RBX(\base), %rbx
    mov CTX_RBP(\base), %rbp
    mov CTX_R12(\base), %r12
    mov CTX_R13(\base), %r13
    mov CTX_R14(\base), %r14
    mov CTX_R15(\base), %r15
    mov CTX_RSP(\base), %rsp
    .if \enable_dispatch
    sti
    .endif
    jmp *CTX_RIP(\base)
.endm

.macro restore_full base
    mov \base, %r11
    test $63, %r11
    jnz 99f
    lea FULL_XSAVE(%r11), %rdi
    cmp FULL_XSAVE_ADDRESS(%r11), %rdi
    jne 99f
    cmpq $0, FULL_XSAVE_BYTES(%r11)
    je 99f
    cmpq $FULL_XSAVE_CAPACITY, FULL_XSAVE_BYTES(%r11)
    ja 99f
    cmpq $3, FULL_XSAVE_FEATURES(%r11)
    jne 99f
    cmpq $0x08, FULL_CS(%r11)
    jne 99f
    cmpq $0x10, FULL_SS(%r11)
    jne 99f
    testq $2, FULL_RFLAGS(%r11)
    jz 99f
    mov FULL_RIP(%r11), %rax
    mov %rax, %rdx
    shl $16, %rdx
    sar $16, %rdx
    cmp %rax, %rdx
    jne 99f
    mov FULL_RSP(%r11), %rax
    test $7, %rax
    jnz 99f
    mov %rax, %rdx
    shl $16, %rdx
    sar $16, %rdx
    cmp %rax, %rdx
    jne 99f
    mov FULL_FS_BASE(%r11), %rax
    mov %rax, %rdx
    shr $32, %rdx
    mov $0xc0000100, %ecx
    wrmsr
    mov $3, %eax
    xor %edx, %edx
    xrstor64 FULL_XSAVE(%r11)
    pushq FULL_SS(%r11)
    pushq FULL_RSP(%r11)
    pushq FULL_RFLAGS(%r11)
    pushq FULL_CS(%r11)
    pushq FULL_RIP(%r11)
    mov FULL_R15(%r11), %r15
    mov FULL_R14(%r11), %r14
    mov FULL_R13(%r11), %r13
    mov FULL_R12(%r11), %r12
    mov FULL_R10(%r11), %r10
    mov FULL_R9(%r11), %r9
    mov FULL_R8(%r11), %r8
    mov FULL_RBP(%r11), %rbp
    mov FULL_RDI(%r11), %rdi
    mov FULL_RSI(%r11), %rsi
    mov FULL_RDX(%r11), %rdx
    mov FULL_RCX(%r11), %rcx
    mov FULL_RBX(%r11), %rbx
    mov FULL_RAX(%r11), %rax
    mov FULL_R11(%r11), %r11
    iretq
99:
    ud2
    jmp 99b
.endm

.global flyology_freestanding_context_switch
.type flyology_freestanding_context_switch, @function
flyology_freestanding_context_switch:
    save_voluntary %rdi
    restore_voluntary %rsi

.global flyology_freestanding_context_switch_to_task
.type flyology_freestanding_context_switch_to_task, @function
flyology_freestanding_context_switch_to_task:
    save_voluntary %rdi
    restore_voluntary %rsi, 1

.global flyology_freestanding_context_capture_full
.type flyology_freestanding_context_capture_full, @function
flyology_freestanding_context_capture_full:
    mov %rdi, %r8
    mov %rsi, %r9
    test $63, %r8
    jnz 99f
    mov $32, %ecx
    rep movsq
    mov FULL_XSAVE_BYTES(%r9), %rcx
    test %rcx, %rcx
    jz 99f
    cmp $FULL_XSAVE_CAPACITY, %rcx
    ja 99f
    mov FULL_XSAVE_ADDRESS(%r9), %rsi
    test %rsi, %rsi
    jz 99f
    lea FULL_XSAVE(%r8), %rdi
    rep movsb
    lea FULL_XSAVE(%r8), %rax
    mov %rax, FULL_XSAVE_ADDRESS(%r8)
    ret
99:
    ud2
    jmp 99b

.global flyology_freestanding_context_restore_from_interrupt
.type flyology_freestanding_context_restore_from_interrupt, @function
flyology_freestanding_context_restore_from_interrupt:
    /*
     * IST entry installs a null SS in 64-bit mode.  A normal IRETQ restores
     * the interrupted selector, but preemption deliberately abandons that frame when
     * it hands control to the dispatcher.  Re-establish the private data
     * selector before resuming ordinary context-switch code so the next
     * interrupt captures the canonical SS expected by the full-frame ABI.
     */
    mov $0x10, %eax
    mov %ax, %ss
    restore_voluntary %rdi

.global flyology_freestanding_context_switch_to_full
.type flyology_freestanding_context_switch_to_full, @function
flyology_freestanding_context_switch_to_full:
    save_voluntary %rdi
    restore_full %rsi

.section .text.flyology_freestanding_context_start, "ax", @progbits
.global flyology_freestanding_context_start
.type flyology_freestanding_context_start, @function
flyology_freestanding_context_start:
    mov %r12, %rdi
    call flyology_freestanding_task_start
1:
    ud2
    jmp 1b

.section .text.flyology_freestanding_dispatcher_context_start, "ax", @progbits
.global flyology_freestanding_dispatcher_context_start
.type flyology_freestanding_dispatcher_context_start, @function
flyology_freestanding_dispatcher_context_start:
    mov %r12, %rdi
    call flyology_freestanding_dispatcher_start
2:
    ud2
    jmp 2b

.section .rodata.flyology_freestanding_context_layout, "a", @progbits
.balign 2
.short CTX_SIZE, CTX_RBX, CTX_RBP, CTX_R12, CTX_R13, CTX_R14
.short CTX_R15, CTX_RSP, CTX_RIP, CTX_MXCSR, CTX_X87_CONTROL, CTX_FS_BASE

.section .rodata.flyology_freestanding_full_context_layout, "a", @progbits
.balign 2
.short FULL_CONTEXT_SIZE, 0, FULL_XSAVE, FULL_RIP, FULL_RFLAGS, FULL_RSP
.short FULL_XSAVE_ADDRESS, FULL_XSAVE_BYTES, FULL_XSAVE_FEATURES

.section .note.GNU-stack, "", @progbits
