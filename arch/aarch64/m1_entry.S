/* SPDX-License-Identifier: MIT OR Apache-2.0 */

.set MAX_CORES, 4
.set STACK_SHIFT, 16
.set CORE_RECORD_SHIFT, 6
.set UART_BASE, 0x09000000

.macro address reg, symbol
    adrp \reg, \symbol
    add  \reg, \reg, :lo12:\symbol
.endm

.section .text.entry, "ax", %progbits
.global _start
.type _start, %function
_start:
    msr daifset, #0xf
    mrs x0, CurrentEL
    lsr x0, x0, #2
    cmp x0, #1
    b.ne fatal

    mrs x0, cpacr_el1
    mov x1, #(3 << 20)
    orr x0, x0, x1
    msr cpacr_el1, x0
    isb

    address x0, vector_table
    msr vbar_el1, x0
    isb

    address x0, core_stacks
    add sp, x0, #(1 << STACK_SHIFT)
    mov x29, xzr
    mov x30, xzr

    address x0, limine_base_revision
    ldr x1, [x0, #16]
    cbnz x1, fatal
    ldr x1, [x0, #8]
    cmp x1, #6
    b.ne fatal

    address x0, limine_hhdm_request
    ldr x0, [x0, #40]
    cbz x0, fatal
    ldr x1, [x0, #0]
    cbnz x1, fatal
    ldr x11, [x0, #8]

    address x0, limine_paging_mode_request
    ldr x0, [x0, #40]
    cbz x0, fatal
    ldr x1, [x0, #0]
    cbnz x1, fatal
    ldr x1, [x0, #8]
    cbnz x1, fatal

    address x0, limine_memmap_request
    ldr x0, [x0, #40]
    cbz x0, fatal
    ldr x1, [x0, #0]
    cbnz x1, fatal
    bl validate_memmap
    address x0, limine_executable_address_request
    ldr x0, [x0, #40]
    cbz x0, fatal
    ldr x3, [x0, #0]
    cbnz x3, fatal
    ldr x1, [x0, #8]
    ldr x2, [x0, #16]
    cbz x1, fatal
    cbz x2, fatal
    bl install_uart_mapping
    bl serial_init
#ifdef FLYOLOGY_M1_FAULT_LAST_CHANCE
    bl flyology_last_chance_probe
#endif

    address x0, limine_mp_request
    ldr x19, [x0, #40]
    cbz x19, fatal
    ldr x0, [x19, #0]
    cbnz x0, fatal
    ldr x20, [x19, #24]
    cbz x20, fatal
    cmp x20, #MAX_CORES
    b.hi fatal
    ldr x21, [x19, #32]
    cbz x21, fatal

    mov x22, xzr
    mov x23, xzr
    mov x24, #1
scan_cpus:
    cmp x23, x20
    b.hs scan_done
    ldr x0, [x21, x23, lsl #3]
    cbz x0, fatal
    mov x25, x0
    mov x26, xzr
validate_unique_cpu:
    cmp x26, x23
    b.hs unique_cpu
    ldr x27, [x21, x26, lsl #3]
    cbz x27, fatal
    cmp x25, x27
    b.eq fatal
    ldr w0, [x25, #0]
    ldr x1, [x25, #8]
    ldr w2, [x27, #0]
    ldr x3, [x27, #8]
    bl flyology_topology_identities_are_distinct
    cbz w0, fatal
    add x26, x26, #1
    b validate_unique_cpu
unique_cpu:
    mov x0, x25
    ldr x1, [x0, #8]
    ldr x2, [x19, #16]
    cmp x1, x2
    b.ne assign_ap
    cbnz x22, fatal
    mov x22, x0
    address x11, core_records
    str xzr, [x11, #0]
    ldr w12, [x0, #0]
    str x12, [x11, #8]
    ldr x12, [x0, #8]
    str x12, [x11, #16]
    str x0, [x11, #24]
    address x12, core_stacks
    add x12, x12, #(1 << STACK_SHIFT)
    str x12, [x11, #32]
    str x11, [x0, #32]
    address x12, bsp_record
    str x11, [x12]
    b scan_next
assign_ap:
    address x11, core_records
    add x11, x11, x24, lsl #CORE_RECORD_SHIFT
    str x24, [x11, #0]
    ldr w12, [x0, #0]
    str x12, [x11, #8]
    ldr x12, [x0, #8]
    str x12, [x11, #16]
    str x0, [x11, #24]
    address x12, core_stacks
    add x13, x24, #1
    lsl x13, x13, #STACK_SHIFT
    add x12, x12, x13
    str x12, [x11, #32]
    str x11, [x0, #32]
    add x24, x24, #1
scan_next:
    add x23, x23, #1
    b scan_cpus
scan_done:
    cbz x22, fatal

    address x0, bsp_record
    ldr x0, [x0]
    cbz x0, fatal
    msr tpidr_el1, x0
    mrs x1, mpidr_el1
    ldr x2, [x0, #16]
    mov x3, #0xffff
    movk x3, #0xff, lsl #16
    movk x3, #0xff, lsl #32
    and x1, x1, x3
    and x2, x2, x3
    cmp x1, x2
    b.ne fatal

    bl adainit
    bl _ada_flyology_m1
    bl adafinal
    address x0, ada_pass
    bl serial_puts_locked

    mov x0, xzr
    bl print_online
    address x0, bsp_record
    ldr x0, [x0]
    add x0, x0, #40
    mov w1, #1
    stlr w1, [x0]
    bl online_increment

    mov x23, xzr
release_loop:
    cmp x23, x20
    b.hs wait_online
    ldr x0, [x21, x23, lsl #3]
    cmp x0, x22
    b.eq release_next
    address x1, ap_entry
    add x2, x0, #24
    stlr x1, [x2]
release_next:
    add x23, x23, #1
    b release_loop

wait_online:
    wfe
    address x0, online_count
    ldar w1, [x0]
    cmp x1, x20
    b.ne wait_online
    address x0, m1_pass
    bl serial_puts_locked
halt:
    wfi
    b halt

.type ap_entry, %function
ap_entry:
    msr daifset, #0xf
    mrs x1, CurrentEL
    lsr x1, x1, #2
    cmp x1, #1
    b.ne fatal
    mrs x1, cpacr_el1
    mov x2, #(3 << 20)
    orr x1, x1, x2
    msr cpacr_el1, x1
    isb
    address x1, vector_table
    msr vbar_el1, x1
    isb
    bl activate_uart_mapping
    ldr x19, [x0, #32]
    cbz x19, fatal
    msr tpidr_el1, x19
    mrs x1, mpidr_el1
    ldr x2, [x19, #16]
    mov x3, #0xffff
    movk x3, #0xff, lsl #16
    movk x3, #0xff, lsl #32
    and x1, x1, x3
    and x2, x2, x3
    cmp x1, x2
    b.ne fatal
    ldr x20, [x19, #0]
    cmp x20, #MAX_CORES
    b.hs fatal
    ldr x1, [x19, #32]
    mov sp, x1
    mov x29, xzr
    mov x30, xzr
    mov x0, x20
    bl print_online
    add x0, x19, #40
    mov w1, #1
    stlr w1, [x0]
    bl online_increment
ap_halt:
    wfi
    b ap_halt

/* x0 = revision-zero memmap response, x11 = HHDM offset. */
.type validate_memmap, %function
validate_memmap:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ldr x19, [x0, #8]
    cbz x19, fatal
    cmp x19, #256
    b.hi fatal
    ldr x20, [x0, #16]
    cbz x20, fatal
    mov x21, x11
    mov x22, xzr
    mov x23, xzr
1:
    cmp x22, x19
    b.hs 4f
    ldr x24, [x20, x22, lsl #3]
    cbz x24, fatal
    ldr x0, [x24, #0]
    ldr x1, [x24, #8]
    ldr x2, [x24, #16]
    mov x3, x21
    bl flyology_memory_entry_is_valid
    cbz w0, fatal
    mov x25, xzr
2:
    cmp x25, x22
    b.hs 3f
    ldr x26, [x20, x25, lsl #3]
    cbz x26, fatal
    ldr x0, [x24, #0]
    ldr x1, [x24, #8]
    ldr x2, [x26, #0]
    ldr x3, [x26, #8]
    bl flyology_memory_entries_are_disjoint
    cbz w0, fatal
    add x25, x25, #1
    b 2b
3:
    ldr x0, [x24, #16]
    cmp x0, #0
    cset x1, eq
    orr x23, x23, x1
    add x22, x22, #1
    b 1b
4:
    cbz x23, fatal
    ldp x29, x30, [sp], #16
    ret

.type online_increment, %function
online_increment:
    address x0, online_count
1:
    ldaxr w1, [x0]
    add w1, w1, #1
    stlxr w2, w1, [x0]
    cbnz w2, 1b
    sev
    ret

/*
 * Limine does not identity-map QEMU virt MMIO. Build a private TTBR0 tree
 * containing one device block for the fixed PL011 window. TTBR1 and all
 * higher-half mappings remain owned by Limine during M1.
 *
 * x1 = executable physical base, x2 = executable virtual base
 */
.type install_uart_mapping, %function
install_uart_mapping:
    stp x29, x30, [sp, #-32]!
    stp x19, x20, [sp, #16]
    mov x29, sp
    mov x19, x1
    mov x20, x2

    address x3, uart_l0
    mov x0, x3
    mov x1, x20
    mov x2, x19
    bl flyology_executable_translation_is_valid
    cbz w0, fatal
    address x3, uart_l0
    subs x4, x3, x20
    b.cc fatal
    adds x4, x4, x19
    b.cs fatal
    address x5, uart_l1
    mov x0, x5
    mov x1, x20
    mov x2, x19
    bl flyology_executable_translation_is_valid
    cbz w0, fatal
    address x5, uart_l1
    subs x6, x5, x20
    b.cc fatal
    adds x6, x6, x19
    b.cs fatal
    address x7, uart_l2
    mov x0, x7
    mov x1, x20
    mov x2, x19
    bl flyology_executable_translation_is_valid
    cbz w0, fatal
    address x7, uart_l2
    subs x8, x7, x20
    b.cc fatal
    adds x8, x8, x19
    b.cs fatal

    orr x9, x6, #3
    str x9, [x3]
    orr x9, x8, #3
    str x9, [x5]

    mov x9, #UART_BASE
    mov x10, #0x61d
    orr x9, x9, x10
    mov x10, #3
    lsl x10, x10, #53
    orr x9, x9, x10
    mov x10, #(UART_BASE >> 21)
    str x9, [x7, x10, lsl #3]

    address x9, uart_l0_physical
    str x4, [x9]
    mov x9, #UART_BASE
    address x10, uart_address
    str x9, [x10]
    bl activate_uart_mapping
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.type activate_uart_mapping, %function
activate_uart_mapping:
    mrs x1, mair_el1
    mov x2, #0xff
    lsl x2, x2, #56
    bic x1, x1, x2
    msr mair_el1, x1
    mrs x1, tcr_el1
    bic x1, x1, #(1 << 7)
    msr tcr_el1, x1
    isb
    address x1, uart_l0_physical
    ldr x1, [x1]
    cbz x1, fatal
    msr ttbr0_el1, x1
    dsb ishst
    tlbi vmalle1
    dsb ish
    isb
    ret

.type print_online, %function
print_online:
    stp x29, x30, [sp, #-32]!
    str x19, [sp, #16]
    mov x29, sp
    mov x19, x0
    bl serial_lock_acquire
    address x0, online_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    mov x0, #'\n'
    bl serial_putc
    bl serial_lock_release
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.type serial_init, %function
serial_init:
    address x0, uart_address
    ldr x0, [x0]
    str wzr, [x0, #0x30]
    mov w1, #13
    str w1, [x0, #0x24]
    mov w1, #1
    str w1, [x0, #0x28]
    mov w1, #0x70
    str w1, [x0, #0x2c]
    mov w1, #0x301
    str w1, [x0, #0x30]
    ret

.global __gnat_last_chance_handler
.global __gnat_rcheck_CE_Explicit_Raise
.global __gnat_rcheck_CE_Range_Check
.global __gnat_rcheck_PE_Explicit_Raise
.global __gnat_rcheck_SE_Explicit_Raise
.type __gnat_last_chance_handler, %function
__gnat_last_chance_handler:
__gnat_rcheck_CE_Explicit_Raise:
__gnat_rcheck_CE_Range_Check:
__gnat_rcheck_PE_Explicit_Raise:
__gnat_rcheck_SE_Explicit_Raise:
    msr daifset, #0xf
    address x0, serial_lock
    stlr wzr, [x0]
    address x0, last_chance_marker
    bl serial_puts
    b halt

.type serial_putc, %function
serial_putc:
    mov w2, w0
    address x1, uart_address
    ldr x1, [x1]
1:
    ldr w3, [x1, #0x18]
    tbnz w3, #5, 1b
    str w2, [x1]
    ret

.type serial_puts, %function
serial_puts:
    stp x29, x30, [sp, #-32]!
    str x19, [sp, #16]
    mov x29, sp
    mov x19, x0
1:
    ldrb w0, [x19], #1
    cbz w0, 2f
    bl serial_putc
    b 1b
2:
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.type serial_puts_locked, %function
serial_puts_locked:
    stp x29, x30, [sp, #-32]!
    str x19, [sp, #16]
    mov x29, sp
    mov x19, x0
    bl serial_lock_acquire
    mov x0, x19
    bl serial_puts
    bl serial_lock_release
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.type serial_lock_acquire, %function
serial_lock_acquire:
    address x0, serial_lock
1:
    ldaxr w1, [x0]
    cbnz w1, 2f
    mov w1, #1
    stxr w2, w1, [x0]
    cbz w2, 3f
2:
    clrex
    wfe
    b 1b
3:
    ret

.type serial_lock_release, %function
serial_lock_release:
    address x0, serial_lock
    stlr wzr, [x0]
    sev
    ret

fatal:
    address x1, uart_address
    ldr x1, [x1]
    cbz x1, halt
    address x0, fail_marker
    bl serial_puts_locked
    b halt

exception_fatal:
    /* M1 vectors are terminal diagnostics; complete frames arrive in M2. */
    msr daifset, #0xf
    address x1, uart_address
    ldr x1, [x1]
    cbz x1, halt
    address x0, serial_lock
    stlr wzr, [x0]
    address x0, exception_marker
    bl serial_puts
    b halt

.balign 2048
vector_table:
    .rept 16
    b exception_fatal
    .balign 128
    .endr

.section .rodata
online_prefix: .asciz "FLYOLOGY:CORE:ONLINE:"
ada_pass:      .asciz "FLYOLOGY:ADA:MAIN:PASS\n"
m1_pass:       .asciz "FLYOLOGY:M1:PASS\n"
fail_marker:   .asciz "FLYOLOGY:FAIL:AARCH64_BOOT\n"
exception_marker: .asciz "FLYOLOGY:FAIL:AARCH64_EXCEPTION\n"
last_chance_marker: .asciz "FLYOLOGY:LAST_CHANCE:AARCH64\n"
digits:        .ascii "0123"

.section .bss
.balign 4
serial_lock: .skip 4
online_count: .skip 4
.balign 8
uart_address: .skip 8
.balign 8
bsp_record: .skip 8
.balign 64
core_records: .skip MAX_CORES * (1 << CORE_RECORD_SHIFT)
.balign 8
uart_l0_physical: .skip 8
.balign 4096
uart_l0: .skip 4096
.balign 4096
uart_l1: .skip 4096
.balign 4096
uart_l2: .skip 4096
.balign 16
core_stacks: .skip MAX_CORES * (1 << STACK_SHIFT)

.section .note.GNU-stack, "", %progbits
