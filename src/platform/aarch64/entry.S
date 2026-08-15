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
.set CORE_PREEMPTION_RETRY_COUNT, 120

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
       EL1h; interrupt substrate tasks later use SP_EL0 while exceptions retain SP_EL1. */
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
#ifdef FLYOLOGY_FAULT_LAST_CHANCE
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
#ifdef FLYOLOGY_INTERRUPTS
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

#ifdef FLYOLOGY_EXCEPTIONS
    bl flyology_exception_initialize
#endif
    bl adainit
#ifdef FLYOLOGY_EXCEPTIONS
#ifndef FLYOLOGY_TASKING
    bl _ada_exception_probe
    address x0, exception_pass
    bl serial_puts_locked
#endif
#endif
#ifdef FLYOLOGY_TASKING
    address x0, ada_elaboration_pass
    bl serial_puts_locked
#endif
#ifdef FLYOLOGY_INTERRUPTS
#ifndef FLYOLOGY_TASKING
    bl _ada_flyology_interrupt_checkpoint
#endif
#else
#if defined(FLYOLOGY_EXCEPTIONS) && !defined(FLYOLOGY_TASKING)
    bl adafinal
#else
    bl _ada_flyology_boot_checkpoint
    bl adafinal
#endif
#endif
#ifndef FLYOLOGY_TASKING
    address x0, ada_pass
    bl serial_puts_locked
#endif

#ifdef FLYOLOGY_INTERRUPTS
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
#ifdef FLYOLOGY_INTERRUPTS
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
#ifdef FLYOLOGY_TASKING
    mov x0, xzr
    bl flyology_kernel_prepare_environment
#else
    bl flyology_interrupts_core_entry
    msr daifset, #2
    bl interrupt_idle_reschedule_test
    bl interrupt_complete_increment
#endif
wait_interrupts_complete:
#ifdef FLYOLOGY_TASKING
    wfe
    address x0, dispatcher_ready_count
    ldar w1, [x0]
    cmp x1, x20
    b.ne wait_interrupts_complete
    msr daifclr, #2
    isb
    bl _ada_flyology_launcher
    address x0, ada_pass
    bl serial_puts_locked
    address x0, tasking_boot_pass
    bl serial_puts_locked
    bl adafinal
    msr daifset, #2
    bl flyology_kernel_environment_complete
    b fatal
#else
    wfe
    address x0, interrupt_complete_count
    ldar w1, [x0]
    cmp x1, x20
    b.ne wait_interrupts_complete
    address x0, interrupt_pass
    bl serial_puts_locked
    bl adafinal
#endif
#else
    address x0, boot_pass
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
#ifdef FLYOLOGY_INTERRUPTS
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
#ifdef FLYOLOGY_TASKING
    mov x0, x20
    bl flyology_kernel_prepare_ap
    b fatal
#else
    bl flyology_interrupts_core_entry
    msr daifset, #2
    bl interrupt_idle_reschedule_test
    bl interrupt_complete_increment
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

#ifdef FLYOLOGY_INTERRUPTS
.type interrupt_complete_increment, %function
interrupt_complete_increment:
    address x0, interrupt_complete_count
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

.type interrupt_idle_ready_increment, %function
interrupt_idle_ready_increment:
    address x0, interrupt_idle_ready_count
1:
    ldaxr w1, [x0]
    add w1, w1, #1
    stlxr w2, w1, [x0]
    cbnz w2, 1b
    sev
    ret

/* x0 = core record, x1 = reason bit. Publish reason before epoch. */
.type interrupt_post_request, %function
interrupt_post_request:
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

.type interrupt_mark_delivered, %function
interrupt_mark_delivered:
    add x2, x0, #72
1:
    ldaxr x3, [x2]
    orr x3, x3, x1
    stlxr w4, x3, [x2]
    cbnz w4, 1b
    sev
    ret

.type interrupt_arm_task_timer, %function
interrupt_arm_task_timer:
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

.global flyology_interrupts_wait_for_timer_request
.type flyology_interrupts_wait_for_timer_request, %function
flyology_interrupts_wait_for_timer_request:
    sub sp, sp, #32
    stp x29, x30, [sp]
    mrs x2, fpcr
    str x2, [sp, #16]
    mov x2, #(1 << 22)
    msr fpcr, x2
    mrs x0, tpidr_el1
    mov x1, #1
    str x1, [x0, #80]
    address x1, interrupt_simd_canary
    ldr q0, [x1]
    ldr q31, [x1, #16]
    bl interrupt_arm_task_timer
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
    address x1, interrupt_simd_canary
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

.global flyology_interrupts_acknowledge_requests
.type flyology_interrupts_acknowledge_requests, %function
flyology_interrupts_acknowledge_requests:
    mrs x1, tpidr_el1
    add x2, x1, #48
    ldar x3, [x2]
    add x2, x1, #56
    stlr x3, [x2]
    add x2, x1, #64
    ldar x0, [x2]
    ret

.global flyology_interrupts_parallel_task_barrier
.type flyology_interrupts_parallel_task_barrier, %function
flyology_interrupts_parallel_task_barrier:
    address x0, interrupt_task_barrier_count
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

.global flyology_interrupts_arm_deferred_timer
.type flyology_interrupts_arm_deferred_timer, %function
flyology_interrupts_arm_deferred_timer:
    stp x29, x30, [sp, #-16]!
    mrs x0, tpidr_el1
    ldr x1, [x0, #72]
    bic x1, x1, #2
    str x1, [x0, #72]
    bl interrupt_arm_task_timer
    mrs x0, tpidr_el1
    add x0, x0, #72
1:
    ldar x1, [x0]
    tbz x1, #1, 1b
    ldp x29, x30, [sp], #16
    ret

.global flyology_interrupts_consume_deferred
.type flyology_interrupts_consume_deferred, %function
flyology_interrupts_consume_deferred:
    mrs x0, tpidr_el1
    add x1, x0, #96
1:
    ldaxr x0, [x1]
    stlxr w2, xzr, [x1]
    cbnz w2, 1b
    ret

.global flyology_platform_disable_dispatch
.type flyology_platform_disable_dispatch, %function
flyology_platform_disable_dispatch:
    msr daifset, #2
    ret

.global flyology_platform_enable_dispatch
.type flyology_platform_enable_dispatch, %function
flyology_platform_enable_dispatch:
    msr daifclr, #2
    isb
    ret

.type interrupt_idle_reschedule_test, %function
interrupt_idle_reschedule_test:
    stp x29, x30, [sp, #-48]!
    stp x19, x20, [sp, #16]
    str x21, [sp, #32]
    mov x29, sp
    mrs x19, tpidr_el1
    str xzr, [x19, #72]
    bl interrupt_idle_ready_increment
    ldr x3, [x19]
    cbnz x3, 3f
1:
    wfe
    address x0, interrupt_idle_ready_count
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
    bl interrupt_post_request
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
    bl flyology_interrupts_acknowledge_requests
    tbz x0, #0, fatal
    ldr x0, [x19]
    bl interrupt_report_sgi_pass
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
    bl flyology_interrupts_acknowledge_requests
    tbz x0, #1, fatal
    ldr x0, [x19]
    bl interrupt_report_timer_pass
    ldp x19, x20, [sp, #16]
    ldr x21, [sp, #32]
    ldp x29, x30, [sp], #48
    ret

.type interrupt_report_sgi_pass, %function
interrupt_report_sgi_pass:
    stp x29, x30, [sp, #-32]!
    str x19, [sp, #16]
    mov x29, sp
    mov x19, x0
    bl serial_lock_acquire
    address x0, interrupt_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, interrupt_sgi_suffix
    bl serial_puts
    bl serial_lock_release
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.type interrupt_report_timer_pass, %function
interrupt_report_timer_pass:
    stp x29, x30, [sp, #-32]!
    str x19, [sp, #16]
    mov x29, sp
    mov x19, x0
    bl serial_lock_acquire
    address x0, interrupt_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, interrupt_timer_suffix
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

#ifdef FLYOLOGY_TASKING
.weak adafinal
.type adafinal, %function
adafinal:
    ret

.global flyology_platform_boot_cpu_count
.type flyology_platform_boot_cpu_count, %function
flyology_platform_boot_cpu_count:
    address x0, cpu_count
    ldr w0, [x0]
    ret

.global flyology_platform_dispatcher_ready
.type flyology_platform_dispatcher_ready, %function
flyology_platform_dispatcher_ready:
    address x0, dispatcher_ready_count
1:
    ldaxr w1, [x0]
    add w1, w1, #1
    stlxr w2, w1, [x0]
    cbnz w2, 1b
    sev
    ret

.global flyology_platform_prepare_idle
.type flyology_platform_prepare_idle, %function
flyology_platform_prepare_idle:
    mrs x0, tpidr_el1
    add x2, x0, #48
    ldar x1, [x2]
    add x2, x0, #56
    stlr x1, [x2]
    ret

.global flyology_platform_idle
.type flyology_platform_idle, %function
flyology_platform_idle:
    msr daifset, #2
    mrs x0, tpidr_el1
    add x3, x0, #48
    ldar x1, [x3]
    add x3, x0, #56
    ldar x2, [x3]
    cmp x1, x2
    b.ne 1f
    wfi
1:
    msr daifclr, #2
    isb
    ret

.global flyology_platform_kick_core
.type flyology_platform_kick_core, %function
flyology_platform_kick_core:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    address x1, cpu_count
    ldr w1, [x1]
    cmp x0, x1
    b.hs fatal
    address x2, core_records
    add x0, x2, x0, lsl #CORE_RECORD_SHIFT
    mov x1, #1
    bl interrupt_post_request
    ldr x0, [x0, #16]
    bl send_reschedule_sgi
    ldp x29, x30, [sp], #16
    ret

.global flyology_conformance_validate_environment_stack
.type flyology_conformance_validate_environment_stack, %function
flyology_conformance_validate_environment_stack:
    address x2, cpu_count
    ldr w2, [x2]
    cmp x0, x2
    b.hs fatal
    address x2, core_records
    add x2, x2, x0, lsl #CORE_RECORD_SHIFT
    ldr x3, [x2, #32]
    sub x2, x3, #(1 << STACK_SHIFT)
    cmp x1, x2
    b.lo 1f
    cmp x1, x3
    b.hs 1f
    mov x0, #1
    ret
1:
    mov x0, xzr
    ret

.global flyology_conformance_report_ordinary_pass
.type flyology_conformance_report_ordinary_pass, %function
flyology_conformance_report_ordinary_pass:
    address x0, tasking_ordinary_pass
    b serial_puts_locked

.global flyology_conformance_report_specific_pass
.type flyology_conformance_report_specific_pass, %function
flyology_conformance_report_specific_pass:
    address x0, tasking_specific_pass
    b serial_puts_locked

.global flyology_conformance_report_parallel_pass
.type flyology_conformance_report_parallel_pass, %function
flyology_conformance_report_parallel_pass:
    address x0, tasking_parallel_pass
    b serial_puts_locked

.global flyology_conformance_report_auto_master_pass
.type flyology_conformance_report_auto_master_pass, %function
flyology_conformance_report_auto_master_pass:
    address x0, tasking_auto_master_pass
    b serial_puts_locked

.global flyology_conformance_report_reclamation_pass
.type flyology_conformance_report_reclamation_pass, %function
flyology_conformance_report_reclamation_pass:
    address x0, rts_reclamation_pass
    b serial_puts_locked

.global flyology_conformance_report_delay_pass
.type flyology_conformance_report_delay_pass, %function
flyology_conformance_report_delay_pass:
    address x0, rts_delay_pass
    b serial_puts_locked

.global flyology_conformance_report_absolute_delay_pass
.type flyology_conformance_report_absolute_delay_pass, %function
flyology_conformance_report_absolute_delay_pass:
    address x0, rts_absolute_delay_pass
    b serial_puts_locked

.global flyology_conformance_report_protected_pass
.type flyology_conformance_report_protected_pass, %function
flyology_conformance_report_protected_pass:
    address x0, rts_protected_pass
    b serial_puts_locked

.global flyology_conformance_report_protected_entry_pass
.type flyology_conformance_report_protected_entry_pass, %function
flyology_conformance_report_protected_entry_pass:
    address x0, rts_protected_entry_pass
    b serial_puts_locked

.global flyology_conformance_report_finalization_pass
.type flyology_conformance_report_finalization_pass, %function
flyology_conformance_report_finalization_pass:
    address x0, rts_finalization_pass
    b serial_puts_locked

.global flyology_conformance_report_rendezvous_pass
.type flyology_conformance_report_rendezvous_pass, %function
flyology_conformance_report_rendezvous_pass:
    address x0, rts_rendezvous_pass
    b serial_puts_locked

.global flyology_conformance_report_exceptional_sync_pass
.type flyology_conformance_report_exceptional_sync_pass, %function
flyology_conformance_report_exceptional_sync_pass:
    address x0, rts_exceptional_sync_pass
    b serial_puts_locked

.global flyology_conformance_report_exceptional_protected_immediate_pass
.type flyology_conformance_report_exceptional_protected_immediate_pass, %function
flyology_conformance_report_exceptional_protected_immediate_pass:
    address x0, rts_exceptional_protected_immediate_pass
    b serial_puts_locked

.global flyology_conformance_report_exceptional_protected_queued_pass
.type flyology_conformance_report_exceptional_protected_queued_pass, %function
flyology_conformance_report_exceptional_protected_queued_pass:
    address x0, rts_exceptional_protected_queued_pass
    b serial_puts_locked

.global flyology_conformance_report_exception_abort_protected_pass
.type flyology_conformance_report_exception_abort_protected_pass, %function
flyology_conformance_report_exception_abort_protected_pass:
    address x0, rts_exception_abort_protected_pass
    b serial_puts_locked

.global flyology_conformance_report_exceptional_rendezvous_pass
.type flyology_conformance_report_exceptional_rendezvous_pass, %function
flyology_conformance_report_exceptional_rendezvous_pass:
    address x0, rts_exceptional_rendezvous_pass
    b serial_puts_locked

.global flyology_conformance_report_exception_abort_pass
.type flyology_conformance_report_exception_abort_pass, %function
flyology_conformance_report_exception_abort_pass:
    address x0, rts_exception_abort_pass
    b serial_puts_locked

.global flyology_conformance_report_unactivated_cleanup_pass
.type flyology_conformance_report_unactivated_cleanup_pass, %function
flyology_conformance_report_unactivated_cleanup_pass:
    address x0, rts_unactivated_cleanup_pass
    b serial_puts_locked

.global flyology_conformance_report_allocator_pass
.type flyology_conformance_report_allocator_pass, %function
flyology_conformance_report_allocator_pass:
    address x0, rts_allocator_pass
    b serial_puts_locked

.global flyology_conformance_report_priority_pass
.type flyology_conformance_report_priority_pass, %function
flyology_conformance_report_priority_pass:
    address x0, rts_priority_pass
    b serial_puts_locked

.global flyology_conformance_report_ceiling_pass
.type flyology_conformance_report_ceiling_pass, %function
flyology_conformance_report_ceiling_pass:
    address x0, rts_ceiling_pass
    b serial_puts_locked

.global flyology_conformance_report_conditional_pass
.type flyology_conformance_report_conditional_pass, %function
flyology_conformance_report_conditional_pass:
    address x0, rts_conditional_pass
    b serial_puts_locked

.global flyology_conformance_report_timed_entry_pass
.type flyology_conformance_report_timed_entry_pass, %function
flyology_conformance_report_timed_entry_pass:
    address x0, rts_timed_entry_pass
    b serial_puts_locked

.global flyology_conformance_report_dynamic_task_pass
.type flyology_conformance_report_dynamic_task_pass, %function
flyology_conformance_report_dynamic_task_pass:
    address x0, rts_dynamic_task_pass
    b serial_puts_locked

.global flyology_conformance_report_free_task_pass
.type flyology_conformance_report_free_task_pass, %function
flyology_conformance_report_free_task_pass:
    address x0, rts_free_task_pass
    b serial_puts_locked

.global flyology_conformance_report_free_wait_pass
.type flyology_conformance_report_free_wait_pass, %function
flyology_conformance_report_free_wait_pass:
    address x0, rts_free_wait_pass
    b serial_puts_locked

.global flyology_conformance_report_free_abort_race_pass
.type flyology_conformance_report_free_abort_race_pass, %function
flyology_conformance_report_free_abort_race_pass:
    address x0, rts_free_abort_race_pass
    b serial_puts_locked

.global flyology_conformance_report_selective_wait_pass
.type flyology_conformance_report_selective_wait_pass, %function
flyology_conformance_report_selective_wait_pass:
    address x0, rts_selective_wait_pass
    b serial_puts_locked

.global flyology_conformance_report_terminate_alternative_pass
.type flyology_conformance_report_terminate_alternative_pass, %function
flyology_conformance_report_terminate_alternative_pass:
    address x0, rts_terminate_alternative_pass
    b serial_puts_locked

.global flyology_conformance_report_abort_pass
.type flyology_conformance_report_abort_pass, %function
flyology_conformance_report_abort_pass:
    address x0, rts_abort_pass
    b serial_puts_locked

.global flyology_conformance_report_multi_abort_pass
.type flyology_conformance_report_multi_abort_pass, %function
flyology_conformance_report_multi_abort_pass:
    address x0, rts_multi_abort_pass
    b serial_puts_locked

.global flyology_conformance_report_dependent_abort_pass
.type flyology_conformance_report_dependent_abort_pass, %function
flyology_conformance_report_dependent_abort_pass:
    address x0, rts_dependent_abort_pass
    b serial_puts_locked

.global flyology_conformance_report_abort_rendezvous_pass
.type flyology_conformance_report_abort_rendezvous_pass, %function
flyology_conformance_report_abort_rendezvous_pass:
    address x0, rts_abort_rendezvous_pass
    b serial_puts_locked

.global flyology_conformance_report_abort_timeout_pass
.type flyology_conformance_report_abort_timeout_pass, %function
flyology_conformance_report_abort_timeout_pass:
    address x0, rts_abort_timeout_pass
    b serial_puts_locked

.global flyology_conformance_report_abort_accepted_pass
.type flyology_conformance_report_abort_accepted_pass, %function
flyology_conformance_report_abort_accepted_pass:
    address x0, rts_abort_accepted_pass
    b serial_puts_locked

.global flyology_conformance_report_abort_protected_pass
.type flyology_conformance_report_abort_protected_pass, %function
flyology_conformance_report_abort_protected_pass:
    address x0, rts_abort_protected_pass
    b serial_puts_locked

.global flyology_conformance_report_collision_stress_pass
.type flyology_conformance_report_collision_stress_pass, %function
flyology_conformance_report_collision_stress_pass:
    address x0, rts_collision_stress_pass
    b serial_puts_locked

.global flyology_conformance_report_fifo_preemption_pass
.type flyology_conformance_report_fifo_preemption_pass, %function
flyology_conformance_report_fifo_preemption_pass:
    address x0, preemption_fifo_preemption_pass
    b serial_puts_locked

.global flyology_conformance_preemption_canary
.type flyology_conformance_preemption_canary, %function
flyology_conformance_preemption_canary:
    sub sp, sp, #304
    str x0, [sp, #0]
    mov x1, sp
    str x1, [sp, #8]
    mrs x1, fpcr
    str x1, [sp, #16]
    mrs x1, fpsr
    str x1, [sp, #24]
    stp q8, q9, [sp, #32]
    stp q10, q11, [sp, #64]
    stp q12, q13, [sp, #96]
    stp q14, q15, [sp, #128]
    stp x18, x19, [sp, #192]
    stp x20, x21, [sp, #208]
    stp x22, x23, [sp, #224]
    stp x24, x25, [sp, #240]
    stp x26, x27, [sp, #256]
    stp x28, x29, [sp, #272]
    str x30, [sp, #288]

    address x16, interrupt_simd_canary
    ldr q0, [x16]
    ldr q1, [x16]
    ldr q2, [x16]
    ldr q3, [x16]
    ldr q4, [x16]
    ldr q5, [x16]
    ldr q6, [x16]
    ldr q7, [x16]
    ldr q8, [x16]
    ldr q9, [x16]
    ldr q10, [x16]
    ldr q11, [x16]
    ldr q12, [x16]
    ldr q13, [x16]
    ldr q14, [x16]
    ldr q15, [x16]
    ldr q16, [x16]
    ldr q17, [x16]
    ldr q18, [x16]
    ldr q19, [x16]
    ldr q20, [x16]
    ldr q21, [x16]
    ldr q22, [x16]
    ldr q23, [x16]
    ldr q24, [x16]
    ldr q25, [x16]
    ldr q26, [x16]
    ldr q27, [x16]
    ldr q28, [x16]
    ldr q29, [x16]
    ldr q30, [x16]
    ldr q31, [x16, #16]
    mov x17, #(1 << 22)
    msr fpcr, x17
    msr fpsr, xzr
    mrs x16, tpidr_el1
    mov x17, #1
    str x17, [x16, #80]

    ldr x0, [sp, #0]
    mov x1, #1
    mov x2, #2
    mov x3, #3
    mov x4, #4
    mov x5, #5
    mov x6, #6
    mov x7, #7
    mov x8, #8
    mov x9, #9
    mov x10, #10
    mov x11, #11
    mov x12, #12
    mov x13, #13
    mov x14, #14
    mov x15, #15
    mov x16, #16
    mov x17, #17
    mov x18, #18
    mov x19, #19
    mov x20, #20
    mov x21, #21
    mov x22, #22
    mov x23, #23
    mov x24, #24
    mov x25, #25
    mov x26, #26
    mov x27, #27
    mov x28, #28
    mov x29, #29
    mov x30, #30
    mov x1, #0xa0000000
    msr nzcv, x1
1:
    ldarb w1, [x0]
    cbz w1, 1b

    mrs x1, nzcv
    lsr x1, x1, #28
    cmp x1, #10
    b.ne preemption_canary_status_fatal
    ldr x1, [sp, #0]
    cmp x0, x1
    b.ne preemption_canary_gpr_fatal
.macro preemption_check_gpr register, value
    cmp \register, #\value
    b.ne preemption_canary_gpr_fatal
.endm
    preemption_check_gpr x2, 2
    preemption_check_gpr x3, 3
    preemption_check_gpr x4, 4
    preemption_check_gpr x5, 5
    preemption_check_gpr x6, 6
    preemption_check_gpr x7, 7
    preemption_check_gpr x8, 8
    preemption_check_gpr x9, 9
    preemption_check_gpr x10, 10
    preemption_check_gpr x11, 11
    preemption_check_gpr x12, 12
    preemption_check_gpr x13, 13
    preemption_check_gpr x14, 14
    preemption_check_gpr x15, 15
    preemption_check_gpr x16, 16
    preemption_check_gpr x17, 17
    preemption_check_gpr x18, 18
    preemption_check_gpr x19, 19
    preemption_check_gpr x20, 20
    preemption_check_gpr x21, 21
    preemption_check_gpr x22, 22
    preemption_check_gpr x23, 23
    preemption_check_gpr x24, 24
    preemption_check_gpr x25, 25
    preemption_check_gpr x26, 26
    preemption_check_gpr x27, 27
    preemption_check_gpr x28, 28
    preemption_check_gpr x29, 29
    preemption_check_gpr x30, 30
.purgem preemption_check_gpr
    mov x1, sp
    ldr x2, [sp, #8]
    cmp x1, x2
    b.ne preemption_canary_gpr_fatal
    mrs x1, fpcr
    cmp x1, #(1 << 22)
    b.ne preemption_canary_fp_fatal
    mrs x1, fpsr
    cbnz x1, preemption_canary_fp_fatal

.macro preemption_check_q register, expected_offset
    str q\register, [sp, #160]
    ldp x2, x3, [sp, #160]
    address x4, interrupt_simd_canary
    ldr x5, [x4, #\expected_offset]
    ldr x6, [x4, #(\expected_offset + 8)]
    cmp x2, x5
    b.ne preemption_canary_simd_fatal
    cmp x3, x6
    b.ne preemption_canary_simd_fatal
.endm
    preemption_check_q 0, 0
    preemption_check_q 1, 0
    preemption_check_q 2, 0
    preemption_check_q 3, 0
    preemption_check_q 4, 0
    preemption_check_q 5, 0
    preemption_check_q 6, 0
    preemption_check_q 7, 0
    preemption_check_q 8, 0
    preemption_check_q 9, 0
    preemption_check_q 10, 0
    preemption_check_q 11, 0
    preemption_check_q 12, 0
    preemption_check_q 13, 0
    preemption_check_q 14, 0
    preemption_check_q 15, 0
    preemption_check_q 16, 0
    preemption_check_q 17, 0
    preemption_check_q 18, 0
    preemption_check_q 19, 0
    preemption_check_q 20, 0
    preemption_check_q 21, 0
    preemption_check_q 22, 0
    preemption_check_q 23, 0
    preemption_check_q 24, 0
    preemption_check_q 25, 0
    preemption_check_q 26, 0
    preemption_check_q 27, 0
    preemption_check_q 28, 0
    preemption_check_q 29, 0
    preemption_check_q 30, 0
    preemption_check_q 31, 16
.purgem preemption_check_q

    mrs x1, tpidr_el1
    str xzr, [x1, #80]
    ldp q8, q9, [sp, #32]
    ldp q10, q11, [sp, #64]
    ldp q12, q13, [sp, #96]
    ldp q14, q15, [sp, #128]
    ldp x18, x19, [sp, #192]
    ldp x20, x21, [sp, #208]
    ldp x22, x23, [sp, #224]
    ldp x24, x25, [sp, #240]
    ldp x26, x27, [sp, #256]
    ldp x28, x29, [sp, #272]
    ldr x30, [sp, #288]
    ldr x1, [sp, #16]
    msr fpcr, x1
    ldr x1, [sp, #24]
    msr fpsr, x1
    add sp, sp, #304
    ret

preemption_canary_status_fatal:
    address x0, preemption_canary_status_failure
    bl serial_puts_locked
    b fatal
preemption_canary_gpr_fatal:
    address x0, preemption_canary_gpr_failure
    bl serial_puts_locked
    b fatal
preemption_canary_simd_fatal:
    address x0, preemption_canary_simd_failure
    bl serial_puts_locked
    b fatal
preemption_canary_fp_fatal:
    address x0, preemption_canary_fp_failure
    bl serial_puts_locked
    b fatal

.global flyology_conformance_report_round_robin_pass
.type flyology_conformance_report_round_robin_pass, %function
flyology_conformance_report_round_robin_pass:
    address x0, preemption_round_robin_pass
    b serial_puts_locked

.global flyology_conformance_report_remote_preemption_pass
.type flyology_conformance_report_remote_preemption_pass, %function
flyology_conformance_report_remote_preemption_pass:
    address x0, preemption_remote_preemption_pass
    b serial_puts_locked

.global flyology_conformance_report_all_core_preemption_pass
.type flyology_conformance_report_all_core_preemption_pass, %function
flyology_conformance_report_all_core_preemption_pass:
    address x0, preemption_all_core_preemption_pass
    b serial_puts_locked

.global flyology_conformance_report_fifo_no_rotation_pass
.type flyology_conformance_report_fifo_no_rotation_pass, %function
flyology_conformance_report_fifo_no_rotation_pass:
    address x0, preemption_fifo_no_rotation_pass
    b serial_puts_locked

.global flyology_conformance_report_priority_requeue_pass
.type flyology_conformance_report_priority_requeue_pass, %function
flyology_conformance_report_priority_requeue_pass:
    address x0, preemption_priority_requeue_pass
    b serial_puts_locked

.global flyology_conformance_report_nonblocking_ingress_pass
.type flyology_conformance_report_nonblocking_ingress_pass, %function
flyology_conformance_report_nonblocking_ingress_pass:
    address x0, preemption_nonblocking_ingress_pass
    b serial_puts_locked

#ifdef FLYOLOGY_DOMAINS
.global flyology_conformance_report_layout_pass
.type flyology_conformance_report_layout_pass, %function
flyology_conformance_report_layout_pass:
    address x0, domain_layout_pass
    b serial_puts_locked

.global flyology_conformance_report_query_pass
.type flyology_conformance_report_query_pass, %function
flyology_conformance_report_query_pass:
    address x0, domain_query_pass
    b serial_puts_locked

.global flyology_conformance_report_inheritance_pass
.type flyology_conformance_report_inheritance_pass, %function
flyology_conformance_report_inheritance_pass:
    address x0, domain_inheritance_pass
    b serial_puts_locked

.global flyology_conformance_report_heterogeneous_pass
.type flyology_conformance_report_heterogeneous_pass, %function
flyology_conformance_report_heterogeneous_pass:
    address x0, domain_heterogeneous_pass
    b serial_puts_locked

.global flyology_conformance_report_all_core_pass
.type flyology_conformance_report_all_core_pass, %function
flyology_conformance_report_all_core_pass:
    address x0, domain_all_core_pass
    b serial_puts_locked

.global flyology_conformance_report_all_core_start_failure
.type flyology_conformance_report_all_core_start_failure, %function
flyology_conformance_report_all_core_start_failure:
    address x0, domain_all_core_start_failure
    b serial_puts_locked

.global flyology_conformance_report_all_core_done_failure
.type flyology_conformance_report_all_core_done_failure, %function
flyology_conformance_report_all_core_done_failure:
    address x0, domain_all_core_done_failure
    b serial_puts_locked
#endif

.global flyology_conformance_report_master_pass
.type flyology_conformance_report_master_pass, %function
flyology_conformance_report_master_pass:
    address x0, tasking_master_pass
    b serial_puts_locked

.global flyology_conformance_report_stack_pass
.type flyology_conformance_report_stack_pass, %function
flyology_conformance_report_stack_pass:
    address x0, tasking_stack_pass
    b serial_puts_locked

.global flyology_conformance_parallel_barrier
.type flyology_conformance_parallel_barrier, %function
flyology_conformance_parallel_barrier:
    cbz x0, fatal
    address x1, cpu_count
    ldr w1, [x1]
    mul w3, w0, w1
    address x0, tasking_parallel_barrier_count
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

.global flyology_platform_read_clock
.type flyology_platform_read_clock, %function
flyology_platform_read_clock:
    isb
    mrs x0, cntvct_el0
    ret

.global flyology_platform_clock_frequency
.type flyology_platform_clock_frequency, %function
flyology_platform_clock_frequency:
    mrs x0, cntfrq_el0
    ret

.global flyology_platform_program_timer
.type flyology_platform_program_timer, %function
flyology_platform_program_timer:
    msr cntv_cval_el0, x0
    mov x0, #1
    msr cntv_ctl_el0, x0
    isb
    ret

.global flyology_platform_cancel_timer
.type flyology_platform_cancel_timer, %function
flyology_platform_cancel_timer:
    msr cntv_ctl_el0, xzr
    isb
    ret

.global flyology_platform_retry_interrupt
.type flyology_platform_retry_interrupt, %function
flyology_platform_retry_interrupt:
    /* Re-enable a bounded local prompt after nonblocking ISR lock failure. */
    mrs x2, tpidr_el1
    add x2, x2, #CORE_PREEMPTION_RETRY_COUNT
    ldr x3, [x2]
    adds x3, x3, #1
    b.cs fatal
    stlr x3, [x2]
    isb
    mrs x0, cntvct_el0
    mrs x1, cntfrq_el0
    lsr x1, x1, #10
    cbnz x1, 1f
    mov x1, #1
1:
    add x0, x0, x1
    msr cntv_cval_el0, x0
    mov x0, #1
    msr cntv_ctl_el0, x0
    isb
    ret

.global flyology_platform_retry_count
.type flyology_platform_retry_count, %function
flyology_platform_retry_count:
    address x1, core_records
    mov x0, xzr
    mov x2, #MAX_CORES
1:
    add x4, x1, #CORE_PREEMPTION_RETRY_COUNT
    ldar x3, [x4]
    adds x0, x0, x3
    b.cs fatal
    add x1, x1, #(1 << CORE_RECORD_SHIFT)
    subs x2, x2, #1
    b.ne 1b
    ret

#ifndef FLYOLOGY_EXCEPTIONS
.global __gnat_personality_v0
.type __gnat_personality_v0, %function
__gnat_personality_v0:
    b fatal

.global _Unwind_Resume
.type _Unwind_Resume, %function
_Unwind_Resume:
    b fatal
#endif
#endif

.global flyology_interrupts_report_pass
.type flyology_interrupts_report_pass, %function
flyology_interrupts_report_pass:
    stp x29, x30, [sp, #-32]!
    str x19, [sp, #16]
    mov x29, sp
    mov x19, x0
    bl serial_lock_acquire
    address x0, interrupt_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, interrupt_core_suffix
    bl serial_puts
    address x0, interrupt_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, interrupt_frame_suffix
    bl serial_puts
    address x0, interrupt_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, interrupt_epoch_suffix
    bl serial_puts
    address x0, interrupt_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, interrupt_parallel_suffix
    bl serial_puts
    address x0, interrupt_core_prefix
    bl serial_puts
    address x1, digits
    ldrb w0, [x1, x19]
    bl serial_putc
    address x0, interrupt_deferred_suffix
    bl serial_puts
    bl serial_lock_release
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.global flyology_conformance_report_failure
.type flyology_conformance_report_failure, %function
flyology_conformance_report_failure:
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

.global flyology_rts_lock_try_acquire
.type flyology_rts_lock_try_acquire, %function
flyology_rts_lock_try_acquire:
    mrs x3, tpidr_el1
    ldr x4, [x3, #88]
    cbnz x4, 2f
    address x0, serial_lock
    ldar w1, [x0]
    cbnz w1, 2f
    address x0, rts_lock
    ldaxr w1, [x0]
    cbnz w1, 1f
    mov w1, #1
    stxr w2, w1, [x0]
    cbnz w2, 2f
    mov x4, #1
    str x4, [x3, #88]
    mov x0, #1
    ret
1:
    clrex
2:
    mov x0, xzr
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
#ifdef FLYOLOGY_PREEMPTION
    ldr x2, [x1, #112]
    cbnz x2, 1f
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    ldr x0, [x1, #16]
    bl send_reschedule_sgi
    ldp x29, x30, [sp], #16
#endif
1:
    ret
#endif

/*
 * Limine does not identity-map QEMU virt MMIO. Build a private TTBR0 tree
 * containing one device block for the fixed PL011 window. TTBR1 and all
 * higher-half mappings remain owned by Limine during bootstrap.
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

#ifdef FLYOLOGY_INTERRUPTS
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
.global __gnat_rcheck_CE_Divide_By_Zero
.global __gnat_rcheck_PE_Explicit_Raise
.global __gnat_rcheck_SE_Explicit_Raise
.type __gnat_last_chance_handler, %function
__gnat_last_chance_handler:
#ifndef FLYOLOGY_EXCEPTIONS
__gnat_rcheck_CE_Explicit_Raise:
__gnat_rcheck_CE_Access_Check:
__gnat_rcheck_CE_Index_Check:
__gnat_rcheck_CE_Invalid_Data:
__gnat_rcheck_CE_Overflow_Check:
__gnat_rcheck_CE_Range_Check:
__gnat_rcheck_CE_Divide_By_Zero:
__gnat_rcheck_PE_Explicit_Raise:
__gnat_rcheck_SE_Explicit_Raise:
#endif
    msr daifset, #0xf
#ifdef FLYOLOGY_EXCEPTIONS
    mov x19, x0
#endif
    address x0, serial_lock
    stlr wzr, [x0]
#ifdef FLYOLOGY_EXCEPTIONS
    address x0, exception_detail
    bl serial_puts
    mov x0, x19
    bl serial_puts
    mov x0, #'\n'
    bl serial_putc
#endif
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

.global flyology_console_puts
.type flyology_console_puts, %function
flyology_console_puts:
    b serial_puts_locked

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
    /* bootstrap vectors are terminal diagnostics; complete frames arrive in interrupt substrate. */
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

#ifdef FLYOLOGY_INTERRUPTS
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
    mrs x0, tpidr_el1
    ldr x1, [x0, #112]
    cmp x1, #255
    b.hs frame_state_fatal
    add x1, x1, #1
    str x1, [x0, #112]
    ldr x0, [sp, #256]
    cbz x0, frame_state_fatal
    ldr x0, [sp, #248]
    tst x0, #15
    b.ne frame_state_fatal
    ldr x0, [sp, #264]
    and x0, x0, #15
    cmp x0, #4
    b.ne frame_state_fatal
#ifndef FLYOLOGY_PREEMPTION
    /*
     * interrupt substrate has no context transfer while its canary is armed.  Under preemption a
     * different task may run on this core before the canary task resumes, so
     * the per-core flag cannot describe the interrupted task's FP/SIMD state.
     * The preemption canary validates its task-owned full continuation after resume.
     */
    mrs x0, tpidr_el1
    ldr x0, [x0, #80]
    cbz x0, 4f
    ldr x0, [sp, #304]
    cmp x0, #(1 << 22)
    b.ne frame_fpcr_fatal
    address x0, interrupt_simd_canary
    ldr q0, [sp, #320]
    ldr q1, [x0]
    cmeq v2.16b, v0.16b, v1.16b
    uminv b2, v2.16b
    umov w0, v2.b[0]
    cmp w0, #0xff
    b.ne frame_simd0_fatal
    address x0, interrupt_simd_canary
    ldr q0, [sp, #816]
    ldr q1, [x0, #16]
    cmeq v2.16b, v0.16b, v1.16b
    uminv b2, v2.16b
    umov w0, v2.b[0]
    cmp w0, #0xff
    b.ne frame_simd31_fatal
4:
#endif
    mrs x20, icc_iar1_el1
    and x1, x20, #0xffffff
    cmp x1, #RESCHEDULE_SGI
    b.ne 1f
    mrs x0, tpidr_el1
    mov x1, #1
    bl interrupt_mark_delivered
    b 2f
1:
    cmp x1, #27
    b.ne 3f
    msr cntv_ctl_el0, xzr
    mrs x0, tpidr_el1
    mov x1, #2
    bl interrupt_post_request
    mrs x0, tpidr_el1
    ldr x1, [x0, #88]
    cbz x1, 5f
    mov x1, #1
    str x1, [x0, #96]
5:
    mrs x0, tpidr_el1
    mov x1, #2
    bl interrupt_mark_delivered
2:
#ifdef FLYOLOGY_PREEMPTION
    mov x21, xzr
    mrs x0, tpidr_el1
    ldr x1, [x0, #88]
    cbnz x1, 6f
    mov x0, sp
    mrs x1, tpidr_el1
    ldr x1, [x1, #0]
    bl flyology_kernel_interrupt_dispatch
    mov x21, x0
6:
#endif
    msr icc_eoir1_el1, x20
    mrs x0, tpidr_el1
    ldr x1, [x0, #112]
    cbz x1, frame_state_fatal
    sub x1, x1, #1
    str x1, [x0, #112]
#ifdef FLYOLOGY_PREEMPTION
    cbz x21, 7f
    mov x0, x21
    b flyology_context_restore_from_interrupt
7:
#endif
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
#ifdef FLYOLOGY_INTERRUPTS
    vector reschedule_irq
#else
    vector exception_fatal
#endif
    vector exception_fatal
    vector exception_fatal
    vector exception_fatal
#ifdef FLYOLOGY_INTERRUPTS
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
interrupt_simd_canary:
.quad 0x0123456789abcdef, 0xfedcba9876543210
.quad 0x55aa55aa33cc33cc, 0xaa55aa55cc33cc33
online_prefix: .asciz "FLYOLOGY:CORE:ONLINE:"
ada_pass:      .asciz "FLYOLOGY:ADA:MAIN:PASS\n"
ada_elaboration_pass: .asciz "FLYOLOGY:ADA:ELABORATION:PASS\n"
boot_pass:       .asciz "FLYOLOGY:BOOT:PASS\n"
exception_pass:.asciz "FLYOLOGY:RTS:EXCEPTION:PASS\n"
exception_detail:.asciz "FLYOLOGY:RTS:EXCEPTION:DETAIL:"
#ifdef FLYOLOGY_INTERRUPTS
interrupt_core_prefix: .asciz "FLYOLOGY:INTERRUPTS:CORE:"
interrupt_core_suffix: .asciz ":SUBSTRATE:PASS\n"
interrupt_frame_suffix: .asciz ":INTERRUPT_FRAME:PASS\n"
interrupt_epoch_suffix: .asciz ":REQUEST_EPOCH:PASS\n"
interrupt_parallel_suffix: .asciz ":PARALLEL:PASS\n"
interrupt_deferred_suffix: .asciz ":DEFERRED_REQUEST:PASS\n"
interrupt_sgi_suffix: .asciz ":RESCHEDULE_SGI:PASS\n"
interrupt_timer_suffix: .asciz ":TIMER:PASS\n"
interrupt_pass:       .asciz "FLYOLOGY:INTERRUPTS:PASS\n"
tasking_boot_pass:  .asciz "FLYOLOGY:TASKING:BOOT_SUBSTRATE:PASS\n"
tasking_ordinary_pass: .asciz "FLYOLOGY:TASKING:ORDINARY_TASKS:PASS\n"
tasking_specific_pass: .asciz "FLYOLOGY:TASKING:SPECIFIC_CPU:PASS\n"
tasking_parallel_pass: .asciz "FLYOLOGY:TASKING:AUTO_PARALLEL:PASS\n"
tasking_auto_master_pass: .asciz "FLYOLOGY:TASKING:AUTO_MASTER:PASS\n"
rts_reclamation_pass: .asciz "FLYOLOGY:RTS:RECLAMATION:PASS\n"
tasking_master_pass: .asciz "FLYOLOGY:TASKING:NESTED_MASTER:PASS\n"
tasking_stack_pass: .asciz "FLYOLOGY:TASKING:TASK_STACKS:PASS\n"
rts_delay_pass: .asciz "FLYOLOGY:RTS:DELAYS:PASS\n"
rts_absolute_delay_pass: .asciz "FLYOLOGY:RTS:ABSOLUTE_DELAY:PASS\n"
rts_protected_pass: .asciz "FLYOLOGY:RTS:PROTECTED:PASS\n"
rts_protected_entry_pass: .asciz "FLYOLOGY:RTS:PROTECTED_ENTRY:PASS\n"
rts_finalization_pass: .asciz "FLYOLOGY:RTS:FINALIZATION:PASS\n"
rts_rendezvous_pass: .asciz "FLYOLOGY:RTS:RENDEZVOUS:PASS\n"
rts_exceptional_sync_pass: .asciz "FLYOLOGY:RTS:EXCEPTIONAL_SYNC:PASS\n"
rts_exceptional_protected_immediate_pass: .asciz "FLYOLOGY:RTS:EXCEPTIONAL_PROTECTED_IMMEDIATE:PASS\n"
rts_exceptional_protected_queued_pass: .asciz "FLYOLOGY:RTS:EXCEPTIONAL_PROTECTED_QUEUED:PASS\n"
rts_exception_abort_protected_pass: .asciz "FLYOLOGY:RTS:EXCEPTION_ABORT_PROTECTED:PASS\n"
rts_exceptional_rendezvous_pass: .asciz "FLYOLOGY:RTS:EXCEPTIONAL_RENDEZVOUS:PASS\n"
rts_exception_abort_pass: .asciz "FLYOLOGY:RTS:EXCEPTION_ABORT:PASS\n"
rts_unactivated_cleanup_pass: .asciz "FLYOLOGY:RTS:UNACTIVATED_CLEANUP:PASS\n"
rts_allocator_pass: .asciz "FLYOLOGY:RTS:ALLOCATOR_TARGET:PASS\n"
rts_priority_pass: .asciz "FLYOLOGY:RTS:DYNAMIC_PRIORITY:PASS\n"
rts_ceiling_pass: .asciz "FLYOLOGY:RTS:CEILING:PASS\n"
rts_conditional_pass: .asciz "FLYOLOGY:RTS:CONDITIONAL_ENTRY:PASS\n"
rts_timed_entry_pass: .asciz "FLYOLOGY:RTS:TIMED_ENTRY:PASS\n"
rts_dynamic_task_pass: .asciz "FLYOLOGY:RTS:DYNAMIC_TASK:PASS\n"
rts_free_task_pass: .asciz "FLYOLOGY:RTS:FREE_TASK:PASS\n"
rts_free_wait_pass: .asciz "FLYOLOGY:RTS:FREE_TASK_WAIT:PASS\n"
rts_free_abort_race_pass: .asciz "FLYOLOGY:RTS:FREE_TASK_ABORT_RACE:PASS\n"
rts_selective_wait_pass: .asciz "FLYOLOGY:RTS:SELECTIVE_WAIT:PASS\n"
rts_terminate_alternative_pass: .asciz "FLYOLOGY:RTS:TERMINATE_ALTERNATIVE:PASS\n"
rts_abort_pass: .asciz "FLYOLOGY:RTS:ABORT:PASS\n"
rts_multi_abort_pass: .asciz "FLYOLOGY:RTS:MULTI_ABORT:PASS\n"
rts_dependent_abort_pass: .asciz "FLYOLOGY:RTS:DEPENDENT_ABORT:PASS\n"
rts_abort_rendezvous_pass: .asciz "FLYOLOGY:RTS:ABORT_RENDEZVOUS:PASS\n"
rts_abort_timeout_pass: .asciz "FLYOLOGY:RTS:ABORT_TIMEOUT:PASS\n"
rts_abort_accepted_pass: .asciz "FLYOLOGY:RTS:ABORT_ACCEPTED:PASS\n"
rts_abort_protected_pass: .asciz "FLYOLOGY:RTS:ABORT_PROTECTED:PASS\n"
rts_collision_stress_pass: .asciz "FLYOLOGY:RTS:COLLISION_STRESS:PASS\n"
preemption_fifo_preemption_pass: .asciz "FLYOLOGY:PREEMPTION:FIFO_PREEMPTION:PASS\n"
preemption_round_robin_pass: .asciz "FLYOLOGY:PREEMPTION:ROUND_ROBIN:PASS\n"
preemption_remote_preemption_pass: .asciz "FLYOLOGY:PREEMPTION:REMOTE_PREEMPTION:PASS\n"
preemption_all_core_preemption_pass: .asciz "FLYOLOGY:PREEMPTION:ALL_CORE_PREEMPTION:PASS\n"
preemption_fifo_no_rotation_pass: .asciz "FLYOLOGY:PREEMPTION:FIFO_NO_ROTATION:PASS\n"
preemption_priority_requeue_pass: .asciz "FLYOLOGY:PREEMPTION:PRIORITY_REQUEUE:PASS\n"
preemption_nonblocking_ingress_pass: .asciz "FLYOLOGY:PREEMPTION:NONBLOCKING_INGRESS:PASS\n"
#ifdef FLYOLOGY_DOMAINS
domain_layout_pass: .asciz "FLYOLOGY:DOMAINS:DOMAIN_LAYOUT:PASS\n"
domain_query_pass: .asciz "FLYOLOGY:DOMAINS:STANDARD_QUERIES:PASS\n"
domain_inheritance_pass: .asciz "FLYOLOGY:DOMAINS:DOMAIN_INHERITANCE:PASS\n"
domain_heterogeneous_pass: .asciz "FLYOLOGY:DOMAINS:HETEROGENEOUS_POLICY:PASS\n"
domain_all_core_pass: .asciz "FLYOLOGY:DOMAINS:ALL_CORE_PREEMPTION:PASS\n"
domain_all_core_start_failure: .asciz "FLYOLOGY:FAIL:DOMAINS_ALL_CORE_START\n"
domain_all_core_done_failure: .asciz "FLYOLOGY:FAIL:DOMAINS_ALL_CORE_DONE\n"
#endif
preemption_canary_status_failure: .asciz "FLYOLOGY:FAIL:AARCH64_CANARY_STATUS\n"
preemption_canary_gpr_failure: .asciz "FLYOLOGY:FAIL:AARCH64_CANARY_GPR\n"
preemption_canary_simd_failure: .asciz "FLYOLOGY:FAIL:AARCH64_CANARY_SIMD\n"
preemption_canary_fp_failure: .asciz "FLYOLOGY:FAIL:AARCH64_CANARY_FP\n"
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
#ifdef FLYOLOGY_INTERRUPTS
interrupt_complete_count: .skip 4
interrupt_idle_ready_count: .skip 4
interrupt_task_barrier_count: .skip 4
cpu_count: .skip 4
rts_lock: .skip 4
#ifdef FLYOLOGY_TASKING
dispatcher_ready_count: .skip 4
tasking_parallel_barrier_count: .skip 4
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
#ifdef FLYOLOGY_INTERRUPTS
.balign 16
exception_stacks: .skip MAX_CORES * (1 << EXCEPTION_STACK_SHIFT)
#endif

.section .note.GNU-stack, "", %progbits
