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

.global flyology_context_switch
.type flyology_context_switch, %function
flyology_context_switch:
    stp x19, x20, [x0, #CTX_X19_X20]
    stp x21, x22, [x0, #CTX_X21_X22]
    stp x23, x24, [x0, #CTX_X23_X24]
    stp x25, x26, [x0, #CTX_X25_X26]
    stp x27, x28, [x0, #CTX_X27_X28]
    stp x29, x30, [x0, #CTX_X29_X30]
    mrs x2, sp_el0
    str x2, [x0, #CTX_SP_EL0]
    stp d8, d9, [x0, #CTX_D8_D9]
    stp d10, d11, [x0, #CTX_D10_D11]
    stp d12, d13, [x0, #CTX_D12_D13]
    stp d14, d15, [x0, #CTX_D14_D15]
    mrs x2, fpcr
    str x2, [x0, #CTX_FPCR]
    mrs x2, fpsr
    str x2, [x0, #CTX_FPSR]

    ldp x19, x20, [x1, #CTX_X19_X20]
    ldp x21, x22, [x1, #CTX_X21_X22]
    ldp x23, x24, [x1, #CTX_X23_X24]
    ldp x25, x26, [x1, #CTX_X25_X26]
    ldp x27, x28, [x1, #CTX_X27_X28]
    ldp x29, x30, [x1, #CTX_X29_X30]
    ldr x2, [x1, #CTX_SP_EL0]
    msr sp_el0, x2
    ldp d8, d9, [x1, #CTX_D8_D9]
    ldp d10, d11, [x1, #CTX_D10_D11]
    ldp d12, d13, [x1, #CTX_D12_D13]
    ldp d14, d15, [x1, #CTX_D14_D15]
    ldr x2, [x1, #CTX_FPCR]
    msr fpcr, x2
    ldr x2, [x1, #CTX_FPSR]
    msr fpsr, x2
    ret

.global flyology_context_start
.type flyology_context_start, %function
flyology_context_start:
    mov x0, x19
    bl flyology_task_start
1:
    brk #0
    b 1b

.section .rodata.flyology_context_layout, "a", %progbits
.balign 2
.short CTX_SIZE, CTX_X19_X20, CTX_X21_X22, CTX_X23_X24
.short CTX_X25_X26, CTX_X27_X28, CTX_X29_X30, CTX_SP_EL0
.short CTX_D8_D9, CTX_D10_D11, CTX_D12_D13, CTX_D14_D15
.short CTX_FPCR, CTX_FPSR

.section .note.GNU-stack, "", %progbits
