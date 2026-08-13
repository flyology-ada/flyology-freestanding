/* SPDX-License-Identifier: MIT OR Apache-2.0 */

.set MAX_CORES, 4
.set STACK_SHIFT, 16
.set EXCEPTION_STACK_SHIFT, 14
.set CORE_RECORD_SHIFT, 7
.set UART_BASE, 0x09000000
.set GICD_BASE, 0x08000000
.set GICR_BASE, 0x080a0000
.set GICR_END, 0x09000000
.set RESCHEDULE_SGI, 1

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

    /* Limine may enter EL1t. Normalize the runtime and owned core stacks to
       EL1h; M2 tasks later use SP_EL0 while exceptions retain SP_EL1. */
    msr spsel, #1
    isb

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
#ifdef FLYOLOGY_M2
    address x0, cpu_count
    str w20, [x0]
#endif

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
#ifdef FLYOLOGY_M3
    address x0, ada_elaboration_pass
    bl serial_puts_locked
#endif
#ifdef FLYOLOGY_M3
    address x0, cpu_count
    ldr w0, [x0]
    bl flyology_m3_core_initialize
#endif
#ifdef FLYOLOGY_M2
#ifndef FLYOLOGY_M3
    bl _ada_flyology_m2
#endif
#else
    bl _ada_flyology_m1
    bl adafinal
#endif
#ifndef FLYOLOGY_M3
    address x0, ada_pass
    bl serial_puts_locked
#endif

#ifdef FLYOLOGY_M2
    bl initialize_gic_distributor
#endif

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
#ifdef FLYOLOGY_M2
    bl initialize_gic_core
    mov x0, sp
    msr sp_el0, x0
    mrs x1, tpidr_el1
    ldr x1, [x1]
    address x2, exception_stacks
    add x1, x1, #1
    add x2, x2, x1, lsl #EXCEPTION_STACK_SHIFT
    mov sp, x2
    msr spsel, #0
    isb
    msr daifclr, #2
    isb
#ifdef FLYOLOGY_M3
    mov x0, xzr
    bl flyology_m3_prepare_environment
#else
    bl flyology_m2_core_entry
    msr daifset, #2
    bl m2_idle_reschedule_test
    bl m2_complete_increment
#endif
wait_m2_complete:
#ifdef FLYOLOGY_M3
    wfe
    address x0, dispatcher_ready_count
    ldar w1, [x0]
    cmp x1, x20
    b.ne wait_m2_complete
    msr daifclr, #2
    isb
    bl _ada_flyology_m3
    address x0, ada_pass
    bl serial_puts_locked
    address x0, m3_boot_pass
    bl serial_puts_locked
    bl adafinal
    msr daifset, #2
    bl flyology_m3_environment_complete
    b fatal
#else
    wfe
    address x0, m2_complete_count
    ldar w1, [x0]
    cmp x1, x20
    b.ne wait_m2_complete
    address x0, m2_pass
    bl serial_puts_locked
    bl adafinal
#endif
#else
    address x0, m1_pass
    bl serial_puts_locked
#endif
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
    msr spsel, #1
    isb
    mov sp, x1
    mov x29, xzr
    mov x30, xzr
    mov x0, x20
    bl print_online
    add x0, x19, #40
    mov w1, #1
    stlr w1, [x0]
    bl online_increment
#ifdef FLYOLOGY_M2
    bl initialize_gic_core
    mov x0, sp
    msr sp_el0, x0
    mrs x1, tpidr_el1
    ldr x1, [x1]
    address x2, exception_stacks
    add x1, x1, #1
    add x2, x2, x1, lsl #EXCEPTION_STACK_SHIFT
    mov sp, x2
    msr spsel, #0
    isb
    msr daifclr, #2
    isb
#ifdef FLYOLOGY_M3
    mov x0, x20
    bl flyology_m3_prepare_ap
    b fatal
#else
    bl flyology_m2_core_entry
    msr daifset, #2
    bl m2_idle_reschedule_test
    bl m2_complete_increment
#endif
#endif
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

#ifdef FLYOLOGY_M2
.type m2_complete_increment, %function
m2_complete_increment:
    address x0, m2_complete_count
1:
    ldaxr w1, [x0]
    add w1, w1, #1
    stlxr w2, w1, [x0]
    cbnz w2, 1b
    sev
    ret

.type initialize_gic_distributor, %function
initialize_gic_distributor:
    mov x0, #GICD_BASE
    str wzr, [x0]
1:
    ldr w1, [x0]
    tbnz w1, #31, 1b
    mov w1, #0x12
    str w1, [x0]
2:
    ldr w1, [x0]
    tbnz w1, #31, 2b
    dsb sy
    ret

.type initialize_gic_core, %function
initialize_gic_core:
    mrs x8, mpidr_el1
    and x9, x8, #0xff
    and x10, x8, #0xff00
    orr x9, x9, x10
    and x10, x8, #0xff0000
    orr x9, x9, x10
    lsr x10, x8, #32
    and x10, x10, #0xff
    lsl x10, x10, #24
    orr x9, x9, x10
    mov x0, #GICR_BASE
    mov x7, #GICR_END
1:
    cmp x0, x7
    b.hs fatal
    ldr x1, [x0, #8]
    lsr x1, x1, #32
    cmp w1, w9
    b.eq 2f
    add x0, x0, #0x20, lsl #12
    b 1b
2:
    ldr w1, [x0, #0x14]
    bic w1, w1, #2
    str w1, [x0, #0x14]
3:
    ldr w1, [x0, #0x14]
    tbnz w1, #2, 3b
    mov x6, x0
    add x0, x0, #0x10, lsl #12
    mov w1, #(1 << RESCHEDULE_SGI)
    mov w2, #(1 << 27)
    orr w1, w1, w2
    str w1, [x0, #0x180]
    dsb sy
4:
    ldr w2, [x6]
    tbnz w2, #3, 4b
    str w1, [x0, #0x80]
    str w1, [x0, #0x280]
    ldr w2, [x0, #0xc04]
    mov w3, #(3 << 22)
    bic w2, w2, w3
    str w2, [x0, #0xc04]
    mov w1, #0x80
    strb w1, [x0, #(0x400 + RESCHEDULE_SGI)]
    strb w1, [x0, #(0x400 + 27)]
    mov w1, #(1 << RESCHEDULE_SGI)
    mov w2, #(1 << 27)
    orr w1, w1, w2
    str w1, [x0, #0x100]
    dsb sy
5:
    ldr w2, [x6]
    tbnz w2, #3, 5b
    mrs x0, icc_sre_el1
    orr x0, x0, #1
    msr icc_sre_el1, x0
    isb
    mrs x0, icc_sre_el1
    tbz x0, #0, fatal
    mov x0, #0xff
    msr icc_pmr_el1, x0
    msr icc_bpr1_el1, xzr
    mrs x0, icc_ctlr_el1
    bic x0, x0, #2
    msr icc_ctlr_el1, x0
    mov x0, #1
    msr icc_igrpen1_el1, x0
    isb
    ret

.type send_reschedule_sgi, %function
send_reschedule_sgi:
    and x1, x0, #0xff
    cmp x1, #15
    b.hi fatal
    mov x2, #1
    lsl x2, x2, x1
    and x3, x0, #0xff00
    lsl x3, x3, #8
    orr x2, x2, x3
    and x3, x0, #0xff0000
    lsl x3, x3, #16
    orr x2, x2, x3
    lsr x3, x0, #32
    and x3, x3, #0xff
    lsl x3, x3, #48
    orr x2, x2, x3
    mov x3, #(RESCHEDULE_SGI << 24)
    orr x2, x2, x3
    dsb ishst
    msr icc_sgi1r_el1, x2
    isb
    ret

.type m2_idle_ready_increment, %function
m2_idle_ready_increment:
    address x0, m2_idle_ready_count
1:
    ldaxr w1, [x0]
    add w1, w1, #1
    stlxr w2, w1, [x0]
    cbnz w2, 1b
    sev
    ret

/* x0 = core record, x1 = reason bit. Publish reason before epoch. */
.type m2_post_request, %function
m2_post_request:
    add x2, x0, #64
1:
    ldaxr x3, [x2]
    orr x3, x3, x1
    stlxr w4, x3, [x2]
    cbnz w4, 1b
    add x2, x0, #48
2:
    ldaxr x3, [x2]
    add x3, x3, #1
    tbnz x3, #63, fatal
    stlxr w4, x3, [x2]
    cbnz w4, 2b
    sev
    ret

.type m2_mark_delivered, %function
m2_mark_delivered:
    add x2, x0, #72
1:
    ldaxr x3, [x2]
    orr x3, x3, x1
    stlxr w4, x3, [x2]
    cbnz w4, 1b
    sev
    ret

.type m2_arm_task_timer, %function
m2_arm_task_timer:
    mrs x0, tpidr_el1
    ldr x1, [x0, #72]
    bic x1, x1, #2
    str x1, [x0, #72]
    mov x0, #0x4000
    msr cntv_tval_el0, x0
    mov x0, #1
    msr cntv_ctl_el0, x0
    isb
    ret

.global flyology_m2_wait_for_timer_request
.type flyology_m2_wait_for_timer_request, %function
flyology_m2_wait_for_timer_request:
    sub sp, sp, #32
    stp x29, x30, [sp]
    mrs x2, fpcr
    str x2, [sp, #16]
    mov x2, #(1 << 22)
    msr fpcr, x2
    mrs x0, tpidr_el1
    mov x1, #1
    str x1, [x0, #80]
    address x1, m2_simd_canary
    ldr q0, [x1]
    ldr q31, [x1, #16]
    bl m2_arm_task_timer
    movz x9, #0x7788
    movk x9, #0x5566, lsl #16
    movk x9, #0x3344, lsl #32
    movk x9, #0x1122, lsl #48
    movz x10, #0x2211
    movk x10, #0x4433, lsl #16
    movk x10, #0x6655, lsl #32
    movk x10, #0x8877, lsl #48
    movz x11, #0xa55a
    movk x11, #0xa55a, lsl #16
    movk x11, #0x5aa5, lsl #32
    movk x11, #0x5aa5, lsl #48
    mrs x0, tpidr_el1
    add x0, x0, #72
1:
    ldar x1, [x0]
    tbz x1, #1, 1b
    movz x1, #0x7788
    movk x1, #0x5566, lsl #16
    movk x1, #0x3344, lsl #32
    movk x1, #0x1122, lsl #48
    cmp x9, x1
    b.ne fatal
    movz x1, #0x2211
    movk x1, #0x4433, lsl #16
    movk x1, #0x6655, lsl #32
    movk x1, #0x8877, lsl #48
    cmp x10, x1
    b.ne fatal
    movz x1, #0xa55a
    movk x1, #0xa55a, lsl #16
    movk x1, #0x5aa5, lsl #32
    movk x1, #0x5aa5, lsl #48
    cmp x11, x1
    b.ne fatal
    address x1, m2_simd_canary
    ldr q1, [x1]
    cmeq v2.16b, v0.16b, v1.16b
    uminv b2, v2.16b
    umov w2, v2.b[0]
    cmp w2, #0xff
    b.ne fatal
    ldr q30, [x1, #16]
    cmeq v2.16b, v31.16b, v30.16b
    uminv b2, v2.16b
    umov w2, v2.b[0]
    cmp w2, #0xff
    b.ne fatal
    mrs x1, fpcr
    cmp x1, #(1 << 22)
    b.ne fatal
    mrs x0, tpidr_el1
    str xzr, [x0, #80]
    ldr x2, [sp, #16]
    msr fpcr, x2
    ldp x29, x30, [sp]
    add sp, sp, #32
    ret

.global flyology_m2_acknowledge_requests
.type flyology_m2_acknowledge_requests, %function
flyology_m2_acknowledge_requests:
    mrs x1, tpidr_el1
    add x2, x1, #48
    ldar x3, [x2]
    add x2, x1, #56
    stlr x3, [x2]
    add x2, x1, #64
    ldar x0, [x2]
    ret

.global flyology_m2_parallel_task_barrier
.type flyology_m2_parallel_task_barrier, %function
flyology_m2_parallel_task_barrier:
    address x0, m2_task_barrier_count
1:
    ldaxr w1, [x0]
    add w1, w1, #1
    stlxr w2, w1, [x0]
    cbnz w2, 1b
2:
    ldar w1, [x0]
    address x2, cpu_count
    ldr w2, [x2]
    cmp w1, w2
    b.eq 3f
    wfe
    b 2b
3:
    sev
    ret

.global flyology_m2_arm_deferred_timer
.type flyology_m2_arm_deferred_timer, %function
flyology_m2_arm_deferred_timer:
    stp x29, x30, [sp, #-16]!
    mrs x0, tpidr_el1
    ldr x1, [x0, #72]
    bic x1, x1, #2
    str x1, [x0, #72]
    bl m2_arm_task_timer
    mrs x0, tpidr_el1
    add x0, x0, #72
1:
    ldar x1, [x0]
    tbz x1, #1, 1b
    ldp x29, x30, [sp], #16
    ret

.global flyology_m2_consume_deferred
.type flyology_m2_consume_deferred, %function
flyology_m2_consume_deferred:
    mrs x0, tpidr_el1
    add x1, x0, #96
1:
    ldaxr x0, [x1]
    stlxr w2, xzr, [x1]
    cbnz w2, 1b
    ret

.global flyology_m2_disable_dispatch
.type flyology_m2_disable_dispatch, %function
flyology_m2_disable_dispatch:
    msr daifset, #2
    ret

.global flyology_m2_enable_dispatch
.type flyology_m2_enable_dispatch, %function
flyology_m2_enable_dispatch:
    msr daifclr, #2
    isb
    ret

.type m2_idle_reschedule_test, %function
m2_idle_reschedule_test:
    stp x29, x30, [sp, #-48]!
    stp x19, x20, [sp, #16]
    str x21, [sp, #32]
    mov x29, sp
    mrs x19, tpidr_el1
    str xzr, [x19, #72]
    bl m2_idle_ready_increment
    ldr x3, [x19]
    cbnz x3, 3f
1:
    wfe
    address x0, m2_idle_ready_count
    ldar w1, [x0]
    address x0, cpu_count
    ldr w20, [x0]
    cmp w1, w20
    b.ne 1b
    mov x21, xzr
2:
    cmp w21, w20
    b.hs 3f
    address x5, core_records
    add x5, x5, x21, lsl #CORE_RECORD_SHIFT
    mov x0, x5
    mov x1, #1
    bl m2_post_request
    ldr x0, [x5, #16]
    bl send_reschedule_sgi
    add x21, x21, #1
    b 2b
3:
    msr daifset, #2
    add x0, x19, #72
    ldar x0, [x0]
    tbnz x0, #0, 4f
    wfi
    msr daifclr, #2
    isb
    msr daifset, #2
    b 3b
4:
    bl flyology_m2_acknowledge_requests
    tbz x0, #0, fatal
    ldr x0, [x19]
    bl m2_report_sgi_pass
    ldr x0, [x19, #72]
    bic x0, x0, #2
    str x0, [x19, #72]
    mov x0, #0x86a0
    movk x0, #1, lsl #16
    msr cntv_tval_el0, x0
    mov x0, #1
    msr cntv_ctl_el0, x0
5:
    msr daifset, #2
    add x0, x19, #72
    ldar x0, [x0]
    tbnz x0, #1, 6f
    wfi
    msr daifclr, #2
    isb
    msr daifset, #2
    b 5b
6:
    bl flyology_m2_acknowledge_requests
    tbz x0, #1, fatal
    ldr x0, [x19]
    bl m2_report_timer_pass
    ldp x19, x20, [sp, #16]
    ldr x21, [sp, #32]
    ldp x29, x30, [sp], #48
    ret

.type m2_report_sgi_pass, %function
m2_report_sgi_pass:
    stp x29, x30, [sp, #-32]!
    str x19, [sp, #16]
    mov x29, sp
    mov x19, x0
    bl serial_lock_acquire
    address x0, m2_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, m2_sgi_suffix
    bl serial_puts
    bl serial_lock_release
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.type m2_report_timer_pass, %function
m2_report_timer_pass:
    stp x29, x30, [sp, #-32]!
    str x19, [sp, #16]
    mov x29, sp
    mov x19, x0
    bl serial_lock_acquire
    address x0, m2_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, m2_timer_suffix
    bl serial_puts
    bl serial_lock_release
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.global flyology_current_core
.type flyology_current_core, %function
flyology_current_core:
    mrs x0, tpidr_el1
    ldr x0, [x0]
    ret

#ifdef FLYOLOGY_M3
.global flyology_m3_dispatcher_ready
.type flyology_m3_dispatcher_ready, %function
flyology_m3_dispatcher_ready:
    address x0, dispatcher_ready_count
1:
    ldaxr w1, [x0]
    add w1, w1, #1
    stlxr w2, w1, [x0]
    cbnz w2, 1b
    sev
    ret

.global flyology_m3_idle
.type flyology_m3_idle, %function
flyology_m3_idle:
    msr daifset, #2
    wfi
    msr daifclr, #2
    isb
    ret

.global flyology_m3_kick_core
.type flyology_m3_kick_core, %function
flyology_m3_kick_core:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    address x1, cpu_count
    ldr w1, [x1]
    cmp x0, x1
    b.hs fatal
    address x2, core_records
    add x0, x2, x0, lsl #CORE_RECORD_SHIFT
    mov x1, #1
    bl m2_post_request
    ldr x0, [x0, #16]
    bl send_reschedule_sgi
    ldp x29, x30, [sp], #16
    ret

.global flyology_m3_report_ordinary_pass
.type flyology_m3_report_ordinary_pass, %function
flyology_m3_report_ordinary_pass:
    address x0, m3_ordinary_pass
    b serial_puts_locked

.global flyology_m3_report_specific_pass
.type flyology_m3_report_specific_pass, %function
flyology_m3_report_specific_pass:
    address x0, m3_specific_pass
    b serial_puts_locked

.global flyology_m3_report_parallel_pass
.type flyology_m3_report_parallel_pass, %function
flyology_m3_report_parallel_pass:
    address x0, m3_parallel_pass
    b serial_puts_locked

.global flyology_m3_parallel_barrier
.type flyology_m3_parallel_barrier, %function
flyology_m3_parallel_barrier:
    cbz x0, fatal
    address x1, cpu_count
    ldr w1, [x1]
    mul w3, w0, w1
    address x0, m3_parallel_barrier_count
1:
    ldaxr w1, [x0]
    add w1, w1, #1
    stlxr w2, w1, [x0]
    cbnz w2, 1b
2:
    ldar w1, [x0]
    cmp w1, w3
    b.eq 3f
    wfe
    b 2b
3:
    sev
    ret

.global __gnat_personality_v0
.type __gnat_personality_v0, %function
__gnat_personality_v0:
    b fatal

.global _Unwind_Resume
.type _Unwind_Resume, %function
_Unwind_Resume:
    b fatal
#endif

.global flyology_m2_report_pass
.type flyology_m2_report_pass, %function
flyology_m2_report_pass:
    stp x29, x30, [sp, #-32]!
    str x19, [sp, #16]
    mov x29, sp
    mov x19, x0
    bl serial_lock_acquire
    address x0, m2_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, m2_core_suffix
    bl serial_puts
    address x0, m2_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, m2_frame_suffix
    bl serial_puts
    address x0, m2_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, m2_epoch_suffix
    bl serial_puts
    address x0, m2_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, m2_parallel_suffix
    bl serial_puts
    address x0, m2_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, m2_deferred_suffix
    bl serial_puts
    bl serial_lock_release
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.global flyology_m2_report_failure
.type flyology_m2_report_failure, %function
flyology_m2_report_failure:
    b fatal

.global flyology_rts_lock_acquire
.type flyology_rts_lock_acquire, %function
flyology_rts_lock_acquire:
    mrs x3, tpidr_el1
    ldr x4, [x3, #88]
    cmp x4, #255
    b.hs fatal
    add x4, x4, #1
    str x4, [x3, #88]
    cmp x4, #1
    b.ne 3f
    address x0, rts_lock
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

.global flyology_rts_lock_release
.type flyology_rts_lock_release, %function
flyology_rts_lock_release:
    mrs x1, tpidr_el1
    ldr x2, [x1, #88]
    cbz x2, fatal
    sub x2, x2, #1
    str x2, [x1, #88]
    cbnz x2, 1f
    address x0, rts_lock
    stlr wzr, [x0]
    sev
    add x2, x1, #48
    ldar x3, [x2]
    ldr x4, [x1, #56]
    cmp x3, x4
    b.eq 1f
    mov x2, #1
    str x2, [x1, #96]
1:
    ret
#endif

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

#ifdef FLYOLOGY_M2
    mov x9, #GICD_BASE
    mov x10, #0x61d
    orr x9, x9, x10
    mov x10, #3
    lsl x10, x10, #53
    orr x9, x9, x10
    mov x10, #(GICD_BASE >> 21)
    mov x12, #8
6:
    str x9, [x7, x10, lsl #3]
    add x9, x9, #0x200, lsl #12
    add x10, x10, #1
    subs x12, x12, #1
    b.ne 6b
#endif

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
.global __gnat_rcheck_CE_Access_Check
.global __gnat_rcheck_CE_Index_Check
.global __gnat_rcheck_CE_Invalid_Data
.global __gnat_rcheck_CE_Overflow_Check
.global __gnat_rcheck_CE_Range_Check
.global __gnat_rcheck_PE_Explicit_Raise
.global __gnat_rcheck_SE_Explicit_Raise
.type __gnat_last_chance_handler, %function
__gnat_last_chance_handler:
__gnat_rcheck_CE_Explicit_Raise:
__gnat_rcheck_CE_Access_Check:
__gnat_rcheck_CE_Index_Check:
__gnat_rcheck_CE_Invalid_Data:
__gnat_rcheck_CE_Overflow_Check:
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
    address x0, exception_marker
    b exception_fatal_message

frame_state_fatal:
    address x0, frame_state_marker
    b exception_fatal_message
frame_fpcr_fatal:
    address x0, frame_fpcr_marker
    b exception_fatal_message
frame_simd0_fatal:
    address x0, frame_simd0_marker
    b exception_fatal_message
frame_simd31_fatal:
    address x0, frame_simd31_marker
exception_fatal_message:
    address x1, uart_address
    ldr x1, [x1]
    cbz x1, halt
    address x1, serial_lock
    stlr wzr, [x1]
    bl serial_puts
    b halt

#ifdef FLYOLOGY_M2
.type reschedule_irq, %function
reschedule_irq:
    sub sp, sp, #832
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    stp x8, x9, [sp, #64]
    stp x10, x11, [sp, #80]
    stp x12, x13, [sp, #96]
    stp x14, x15, [sp, #112]
    stp x16, x17, [sp, #128]
    stp x18, x19, [sp, #144]
    stp x20, x21, [sp, #160]
    stp x22, x23, [sp, #176]
    stp x24, x25, [sp, #192]
    stp x26, x27, [sp, #208]
    stp x28, x29, [sp, #224]
    str x30, [sp, #240]
    mrs x0, sp_el0
    str x0, [sp, #248]
    mrs x0, elr_el1
    str x0, [sp, #256]
    mrs x0, spsr_el1
    str x0, [sp, #264]
    mrs x0, esr_el1
    str x0, [sp, #272]
    mrs x0, far_el1
    str x0, [sp, #280]
    mrs x0, tpidr_el0
    str x0, [sp, #288]
    mov x0, #1
    str x0, [sp, #296]
    mrs x0, fpcr
    str x0, [sp, #304]
    mrs x0, fpsr
    str x0, [sp, #312]
    stp q0, q1, [sp, #320]
    stp q2, q3, [sp, #352]
    stp q4, q5, [sp, #384]
    stp q6, q7, [sp, #416]
    stp q8, q9, [sp, #448]
    stp q10, q11, [sp, #480]
    stp q12, q13, [sp, #512]
    stp q14, q15, [sp, #544]
    stp q16, q17, [sp, #576]
    stp q18, q19, [sp, #608]
    stp q20, q21, [sp, #640]
    stp q22, q23, [sp, #672]
    stp q24, q25, [sp, #704]
    stp q26, q27, [sp, #736]
    stp q28, q29, [sp, #768]
    stp q30, q31, [sp, #800]
    ldr x0, [sp, #256]
    cbz x0, frame_state_fatal
    ldr x0, [sp, #248]
    tst x0, #15
    b.ne frame_state_fatal
    ldr x0, [sp, #264]
    and x0, x0, #15
    cmp x0, #4
    b.ne frame_state_fatal
    mrs x0, tpidr_el1
    ldr x0, [x0, #80]
    cbz x0, 4f
    ldr x0, [sp, #304]
    cmp x0, #(1 << 22)
    b.ne frame_fpcr_fatal
    address x0, m2_simd_canary
    ldr q0, [sp, #320]
    ldr q1, [x0]
    cmeq v2.16b, v0.16b, v1.16b
    uminv b2, v2.16b
    umov w0, v2.b[0]
    cmp w0, #0xff
    b.ne frame_simd0_fatal
    address x0, m2_simd_canary
    ldr q0, [sp, #816]
    ldr q1, [x0, #16]
    cmeq v2.16b, v0.16b, v1.16b
    uminv b2, v2.16b
    umov w0, v2.b[0]
    cmp w0, #0xff
    b.ne frame_simd31_fatal
4:
    mrs x20, icc_iar1_el1
    and x1, x20, #0xffffff
    cmp x1, #RESCHEDULE_SGI
    b.ne 1f
    mrs x0, tpidr_el1
    mov x1, #1
    bl m2_mark_delivered
    b 2f
1:
    cmp x1, #27
    b.ne 3f
    msr cntv_ctl_el0, xzr
    mrs x0, tpidr_el1
    mov x1, #2
    bl m2_post_request
    mrs x0, tpidr_el1
    ldr x1, [x0, #88]
    cbz x1, 5f
    mov x1, #1
    str x1, [x0, #96]
5:
    mrs x0, tpidr_el1
    mov x1, #2
    bl m2_mark_delivered
2:
    msr icc_eoir1_el1, x20
    ldp q0, q1, [sp, #320]
    ldp q2, q3, [sp, #352]
    ldp q4, q5, [sp, #384]
    ldp q6, q7, [sp, #416]
    ldp q8, q9, [sp, #448]
    ldp q10, q11, [sp, #480]
    ldp q12, q13, [sp, #512]
    ldp q14, q15, [sp, #544]
    ldp q16, q17, [sp, #576]
    ldp q18, q19, [sp, #608]
    ldp q20, q21, [sp, #640]
    ldp q22, q23, [sp, #672]
    ldp q24, q25, [sp, #704]
    ldp q26, q27, [sp, #736]
    ldp q28, q29, [sp, #768]
    ldp q30, q31, [sp, #800]
    ldr x0, [sp, #304]
    msr fpcr, x0
    ldr x0, [sp, #312]
    msr fpsr, x0
    ldr x0, [sp, #248]
    msr sp_el0, x0
    ldr x0, [sp, #256]
    msr elr_el1, x0
    ldr x0, [sp, #264]
    msr spsr_el1, x0
    ldr x0, [sp, #288]
    msr tpidr_el0, x0
    ldp x0, x1, [sp, #0]
    ldp x2, x3, [sp, #16]
    ldp x4, x5, [sp, #32]
    ldp x6, x7, [sp, #48]
    ldp x8, x9, [sp, #64]
    ldp x10, x11, [sp, #80]
    ldp x12, x13, [sp, #96]
    ldp x14, x15, [sp, #112]
    ldp x16, x17, [sp, #128]
    ldp x18, x19, [sp, #144]
    ldp x20, x21, [sp, #160]
    ldp x22, x23, [sp, #176]
    ldp x24, x25, [sp, #192]
    ldp x26, x27, [sp, #208]
    ldp x28, x29, [sp, #224]
    ldr x30, [sp, #240]
    add sp, sp, #832
    eret
3:
    msr icc_eoir1_el1, x20
    add sp, sp, #832
    b exception_fatal
#endif

.balign 2048
vector_table:
.macro vector target
    b \target
    .balign 128
.endm
    vector exception_fatal
#ifdef FLYOLOGY_M2
    vector reschedule_irq
#else
    vector exception_fatal
#endif
    vector exception_fatal
    vector exception_fatal
    vector exception_fatal
#ifdef FLYOLOGY_M2
    vector reschedule_irq
#else
    vector exception_fatal
#endif
    vector exception_fatal
    vector exception_fatal
    vector exception_fatal
    vector exception_fatal
    vector exception_fatal
    vector exception_fatal
    vector exception_fatal
    vector exception_fatal
    vector exception_fatal
    vector exception_fatal

.section .rodata.flyology_interrupt_layout, "a", %progbits
.short 832, 0, 248, 256, 264, 272, 280, 288
.short 296, 304, 312, 320

.section .rodata
.balign 16
m2_simd_canary:
.quad 0x0123456789abcdef, 0xfedcba9876543210
.quad 0x55aa55aa33cc33cc, 0xaa55aa55cc33cc33
online_prefix: .asciz "FLYOLOGY:CORE:ONLINE:"
ada_pass:      .asciz "FLYOLOGY:ADA:MAIN:PASS\n"
ada_elaboration_pass: .asciz "FLYOLOGY:ADA:ELABORATION:PASS\n"
m1_pass:       .asciz "FLYOLOGY:M1:PASS\n"
#ifdef FLYOLOGY_M2
m2_core_prefix: .asciz "FLYOLOGY:M2:CORE:"
m2_core_suffix: .asciz ":SUBSTRATE:PASS\n"
m2_frame_suffix: .asciz ":INTERRUPT_FRAME:PASS\n"
m2_epoch_suffix: .asciz ":REQUEST_EPOCH:PASS\n"
m2_parallel_suffix: .asciz ":PARALLEL:PASS\n"
m2_deferred_suffix: .asciz ":DEFERRED_REQUEST:PASS\n"
m2_sgi_suffix: .asciz ":RESCHEDULE_SGI:PASS\n"
m2_timer_suffix: .asciz ":TIMER:PASS\n"
m2_pass:       .asciz "FLYOLOGY:M2:PASS\n"
m3_boot_pass:  .asciz "FLYOLOGY:M3:BOOT_SUBSTRATE:PASS\n"
m3_ordinary_pass: .asciz "FLYOLOGY:M3:ORDINARY_TASKS:PASS\n"
m3_specific_pass: .asciz "FLYOLOGY:M3:SPECIFIC_CPU:PASS\n"
m3_parallel_pass: .asciz "FLYOLOGY:M3:AUTO_PARALLEL:PASS\n"
#endif
fail_marker:   .asciz "FLYOLOGY:FAIL:AARCH64_BOOT\n"
exception_marker: .asciz "FLYOLOGY:FAIL:AARCH64_EXCEPTION\n"
frame_state_marker: .asciz "FLYOLOGY:FAIL:AARCH64_FRAME_STATE\n"
frame_fpcr_marker: .asciz "FLYOLOGY:FAIL:AARCH64_FRAME_FPCR\n"
frame_simd0_marker: .asciz "FLYOLOGY:FAIL:AARCH64_FRAME_SIMD0\n"
frame_simd31_marker: .asciz "FLYOLOGY:FAIL:AARCH64_FRAME_SIMD31\n"
last_chance_marker: .asciz "FLYOLOGY:LAST_CHANCE:AARCH64\n"
digits:        .ascii "0123"

.section .bss
.balign 4
serial_lock: .skip 4
online_count: .skip 4
#ifdef FLYOLOGY_M2
m2_complete_count: .skip 4
m2_idle_ready_count: .skip 4
m2_task_barrier_count: .skip 4
cpu_count: .skip 4
rts_lock: .skip 4
#ifdef FLYOLOGY_M3
dispatcher_ready_count: .skip 4
m3_parallel_barrier_count: .skip 4
#endif
#endif
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
#ifdef FLYOLOGY_M2
.balign 16
exception_stacks: .skip MAX_CORES * (1 << EXCEPTION_STACK_SHIFT)
#endif

.section .note.GNU-stack, "", %progbits
