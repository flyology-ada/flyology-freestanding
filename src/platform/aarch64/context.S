/* SPDX-License-Identifier: MIT OR Apache-2.0 */

/*
 * Voluntary AAPCS64 context. The exact 192-byte layout is mirrored by
 * flyology-architecture_context.ads.
 */
.section .text, "ax", %progbits
.equ CTX_X19_X20, 0
.equ CTX_X21_X22, 16
.equ CTX_X23_X24, 32
.equ CTX_X25_X26, 48
.equ CTX_X27_X28, 64
.equ CTX_X29_X30, 80
.equ CTX_SP_EL0, 96
.equ CTX_D8_D9, 112
.equ CTX_D10_D11, 128
.equ CTX_D12_D13, 144
.equ CTX_D14_D15, 160
.equ CTX_FPCR, 176
.equ CTX_FPSR, 184
.equ CTX_SIZE, 192

.equ FULL_X0_X1, 0
.equ FULL_X2_X3, 16
.equ FULL_X4_X5, 32
.equ FULL_X6_X7, 48
.equ FULL_X8_X9, 64
.equ FULL_X10_X11, 80
.equ FULL_X12_X13, 96
.equ FULL_X14_X15, 112
.equ FULL_X16_X17, 128
.equ FULL_X18_X19, 144
.equ FULL_X20_X21, 160
.equ FULL_X22_X23, 176
.equ FULL_X24_X25, 192
.equ FULL_X26_X27, 208
.equ FULL_X28_X29, 224
.equ FULL_X30, 240
.equ FULL_SP_EL0, 248
.equ FULL_ELR, 256
.equ FULL_SPSR, 264
.equ FULL_TPIDR_EL0, 288
.equ FULL_FPCR, 304
.equ FULL_FPSR, 312
.equ FULL_SIMD, 320
.equ FULL_CONTEXT_SIZE, 832

.macro save_voluntary base
    stp x19, x20, [\base, #CTX_X19_X20]
    stp x21, x22, [\base, #CTX_X21_X22]
    stp x23, x24, [\base, #CTX_X23_X24]
    stp x25, x26, [\base, #CTX_X25_X26]
    stp x27, x28, [\base, #CTX_X27_X28]
    stp x29, x30, [\base, #CTX_X29_X30]
    mov x2, sp
    str x2, [\base, #CTX_SP_EL0]
    stp d8, d9, [\base, #CTX_D8_D9]
    stp d10, d11, [\base, #CTX_D10_D11]
    stp d12, d13, [\base, #CTX_D12_D13]
    stp d14, d15, [\base, #CTX_D14_D15]
    mrs x2, fpcr
    str x2, [\base, #CTX_FPCR]
    mrs x2, fpsr
    str x2, [\base, #CTX_FPSR]
.endm

.macro restore_voluntary base, enable_dispatch=0
    ldp x19, x20, [\base, #CTX_X19_X20]
    ldp x21, x22, [\base, #CTX_X21_X22]
    ldp x23, x24, [\base, #CTX_X23_X24]
    ldp x25, x26, [\base, #CTX_X25_X26]
    ldp x27, x28, [\base, #CTX_X27_X28]
    ldp x29, x30, [\base, #CTX_X29_X30]
    ldr x2, [\base, #CTX_SP_EL0]
    mov sp, x2
    ldp d8, d9, [\base, #CTX_D8_D9]
    ldp d10, d11, [\base, #CTX_D10_D11]
    ldp d12, d13, [\base, #CTX_D12_D13]
    ldp d14, d15, [\base, #CTX_D14_D15]
    ldr x2, [\base, #CTX_FPCR]
    msr fpcr, x2
    ldr x2, [\base, #CTX_FPSR]
    msr fpsr, x2
    .if \enable_dispatch
    msr daifclr, #2
    isb
    .endif
    ret
.endm

.global flyology_context_switch
.type flyology_context_switch, %function
flyology_context_switch:
    /* Voluntary paths execute with SPSel=0. Accessing SP_EL0 through MRS/MSR
       while it is current is undefined; the architectural SP operand is the
       same task stack and is valid in this state. */
    save_voluntary x0
    restore_voluntary x1

.global flyology_context_switch_to_task
.type flyology_context_switch_to_task, %function
flyology_context_switch_to_task:
    save_voluntary x0
    restore_voluntary x1, 1

.global flyology_context_restore_from_interrupt
.type flyology_context_restore_from_interrupt, %function
flyology_context_restore_from_interrupt:
    add sp, sp, #FULL_CONTEXT_SIZE
    msr spsel, #0
    restore_voluntary x0

.global flyology_context_switch_to_full
.type flyology_context_switch_to_full, %function
flyology_context_switch_to_full:
    save_voluntary x0
    mov x18, x1
    tst x18, #15
    b.ne 99f
    ldr x2, [x18, #FULL_ELR]
    cbz x2, 99f
    ldr x2, [x18, #FULL_SP_EL0]
    tst x2, #15
    b.ne 99f
    ldr x2, [x18, #FULL_SPSR]
    and x2, x2, #15
    cmp x2, #4
    b.ne 99f
    msr spsel, #1
    ldp q0, q1, [x18, #FULL_SIMD]
    ldp q2, q3, [x18, #(FULL_SIMD + 32)]
    ldp q4, q5, [x18, #(FULL_SIMD + 64)]
    ldp q6, q7, [x18, #(FULL_SIMD + 96)]
    ldp q8, q9, [x18, #(FULL_SIMD + 128)]
    ldp q10, q11, [x18, #(FULL_SIMD + 160)]
    ldp q12, q13, [x18, #(FULL_SIMD + 192)]
    ldp q14, q15, [x18, #(FULL_SIMD + 224)]
    ldp q16, q17, [x18, #(FULL_SIMD + 256)]
    ldp q18, q19, [x18, #(FULL_SIMD + 288)]
    ldp q20, q21, [x18, #(FULL_SIMD + 320)]
    ldp q22, q23, [x18, #(FULL_SIMD + 352)]
    ldp q24, q25, [x18, #(FULL_SIMD + 384)]
    ldp q26, q27, [x18, #(FULL_SIMD + 416)]
    ldp q28, q29, [x18, #(FULL_SIMD + 448)]
    ldp q30, q31, [x18, #(FULL_SIMD + 480)]
    ldr x2, [x18, #FULL_FPCR]
    msr fpcr, x2
    ldr x2, [x18, #FULL_FPSR]
    msr fpsr, x2
    ldr x2, [x18, #FULL_SP_EL0]
    msr sp_el0, x2
    ldr x2, [x18, #FULL_ELR]
    msr elr_el1, x2
    ldr x2, [x18, #FULL_SPSR]
    msr spsr_el1, x2
    ldr x2, [x18, #FULL_TPIDR_EL0]
    msr tpidr_el0, x2
    ldp x0, x1, [x18, #FULL_X0_X1]
    ldp x2, x3, [x18, #FULL_X2_X3]
    ldp x4, x5, [x18, #FULL_X4_X5]
    ldp x6, x7, [x18, #FULL_X6_X7]
    ldp x8, x9, [x18, #FULL_X8_X9]
    ldp x10, x11, [x18, #FULL_X10_X11]
    ldp x12, x13, [x18, #FULL_X12_X13]
    ldp x14, x15, [x18, #FULL_X14_X15]
    ldp x16, x17, [x18, #FULL_X16_X17]
    ldr x19, [x18, #(FULL_X18_X19 + 8)]
    ldp x20, x21, [x18, #FULL_X20_X21]
    ldp x22, x23, [x18, #FULL_X22_X23]
    ldp x24, x25, [x18, #FULL_X24_X25]
    ldp x26, x27, [x18, #FULL_X26_X27]
    ldp x28, x29, [x18, #FULL_X28_X29]
    ldr x30, [x18, #FULL_X30]
    ldr x18, [x18, #FULL_X18_X19]
    eret
99:
    brk #0
    b 99b

.section .text.flyology_context_start, "ax", %progbits
.global flyology_context_start
.type flyology_context_start, %function
flyology_context_start:
    mov x0, x19
    bl flyology_task_start
1:
    brk #0
    b 1b

.section .text.flyology_dispatcher_context_start, "ax", %progbits
.global flyology_dispatcher_context_start
.type flyology_dispatcher_context_start, %function
flyology_dispatcher_context_start:
    mov x0, x19
    bl flyology_dispatcher_start
2:
    brk #0
    b 2b

.section .rodata.flyology_context_layout, "a", %progbits
.balign 2
.short CTX_SIZE, CTX_X19_X20, CTX_X21_X22, CTX_X23_X24
.short CTX_X25_X26, CTX_X27_X28, CTX_X29_X30, CTX_SP_EL0
.short CTX_D8_D9, CTX_D10_D11, CTX_D12_D13, CTX_D14_D15
.short CTX_FPCR, CTX_FPSR

.section .rodata.flyology_full_context_layout, "a", %progbits
.balign 2
.short FULL_CONTEXT_SIZE, 0, FULL_SP_EL0, FULL_ELR, FULL_SPSR
.short FULL_TPIDR_EL0, FULL_FPCR, FULL_FPSR, FULL_SIMD

.section .note.GNU-stack, "", %progbits
