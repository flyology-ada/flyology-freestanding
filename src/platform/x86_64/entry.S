/* SPDX-License-Identifier: MIT OR Apache-2.0 */

.set MAX_CORES, 4
.set STACK_SHIFT, 16
.set EXCEPTION_STACK_SHIFT, 14
.set CORE_RECORD_SHIFT, 7
.set COM1, 0x3f8
.set TIMER_VECTOR, 0xe0
.set RESCHEDULE_VECTOR, 0xe1
.set IDT_TRANSITION_VECTOR, 0xe2
.set GDT_SHIFT, 12
.set GDT_LIMIT, 4079
.set GDT_DESCRIPTOR_OFFSET, 4080
.set CORE_PREEMPTION_RETRY_COUNT, 120

.section .text.entry, "ax", @progbits
.global _start
.type _start, @function
_start:
    cli
    cld
    lea core_stacks + (1 << STACK_SHIFT)(%rip), %rsp
    xor %ebp, %ebp
    call serial_init
    call initialize_idt
#if defined(FLYOLOGY_TASKING) || defined(FLYOLOGY_EXCEPTIONS)
    /* Base revision 6 disables FP/SIMD.  No compiler-generated Ada call may
       precede normalization, including the injected last-chance probe. */
#ifdef FLYOLOGY_EXCEPTIONS
    call initialize_exception_fp
#else
    call initialize_task_fp
#endif
#endif
#ifdef FLYOLOGY_FAULT_LAST_CHANCE
    call flyology_last_chance_probe
#endif

    cmpq $0, limine_base_revision + 16(%rip)
    jne fatal
    cmpq $6, limine_base_revision + 8(%rip)
    jne fatal

    mov limine_paging_mode_request + 40(%rip), %rax
    test %rax, %rax
    jz fatal
    cmpq $0, 0(%rax)
    jne fatal
    cmpq $0, 8(%rax)
    jne fatal

    mov limine_hhdm_request + 40(%rip), %rax
    test %rax, %rax
    jz fatal
    cmpq $0, 0(%rax)
    jne fatal
    mov 8(%rax), %r15
    mov limine_memmap_request + 40(%rip), %rdi
    test %rdi, %rdi
    jz fatal
    cmpq $0, 0(%rdi)
    jne fatal
    call validate_memmap
    mov limine_executable_address_request + 40(%rip), %rax
    test %rax, %rax
    jz fatal
    cmpq $0, 0(%rax)
    jne fatal
    cmpq $0, 8(%rax)
    je fatal
    cmpq $0, 16(%rax)
    je fatal

    mov limine_mp_request + 40(%rip), %r12
    test %r12, %r12
    jz fatal
    cmpq $0, 0(%r12)
    jne fatal
    testl $1, 8(%r12)
    jz fatal
    mov 16(%r12), %r13
    test %r13, %r13
    jz fatal
    cmp $MAX_CORES, %r13
    ja fatal
    mov 24(%r12), %r14
    test %r14, %r14
    jz fatal

    xor %r15d, %r15d
    xor %ebx, %ebx
    mov $1, %rbp
scan_cpus:
    cmp %r13, %rbx
    jae scan_done
    mov (%r14,%rbx,8), %rdi
    test %rdi, %rdi
    jz fatal
    xor %ecx, %ecx
validate_unique_cpu:
    cmp %rbx, %rcx
    jae unique_cpu
    mov (%r14,%rcx,8), %rax
    cmp %rdi, %rax
    je fatal
    test %rax, %rax
    jz fatal
    mov 0(%rdi), %edx
    cmp 0(%rax), %edx
    je fatal
    mov 4(%rdi), %edx
    cmp 4(%rax), %edx
    je fatal
    push %rcx
    push %rdi
    mov 4(%rdi), %esi
    mov 0(%rdi), %edi
    mov (%r14,%rcx,8), %rax
    mov 0(%rax), %edx
    mov 4(%rax), %ecx
    call flyology_topology_identities_are_distinct
    pop %rdi
    pop %rcx
    test %eax, %eax
    jz fatal
    inc %rcx
    jmp validate_unique_cpu
unique_cpu:
    mov 4(%rdi), %eax
    cmp 12(%r12), %eax
    jne assign_ap
    test %r15, %r15
    jnz fatal
    mov %rdi, %r15
    lea core_records(%rip), %r11
    movq $0, 0(%r11)
    mov 0(%rdi), %eax
    mov %rax, 8(%r11)
    mov 4(%rdi), %eax
    mov %rax, 16(%r11)
    mov %rdi, 24(%r11)
    lea core_stacks + (1 << STACK_SHIFT)(%rip), %rax
    mov %rax, 32(%r11)
    mov %r11, 24(%rdi)
    mov %r11, bsp_record(%rip)
    jmp scan_next
assign_ap:
    lea core_records(%rip), %r11
    mov %rbp, %rax
    shl $CORE_RECORD_SHIFT, %rax
    add %rax, %r11
    mov %rbp, 0(%r11)
    mov 0(%rdi), %eax
    mov %rax, 8(%r11)
    mov 4(%rdi), %eax
    mov %rax, 16(%r11)
    mov %rdi, 24(%r11)
    lea core_stacks(%rip), %rax
    mov %rbp, %rcx
    inc %rcx
    shl $STACK_SHIFT, %rcx
    add %rcx, %rax
    mov %rax, 32(%r11)
    mov %r11, 24(%rdi)
    inc %rbp
scan_next:
    inc %rbx
    jmp scan_cpus
scan_done:
    test %r15, %r15
    jz fatal
#ifdef FLYOLOGY_INTERRUPTS
    mov %r13d, cpu_count(%rip)
#endif

    mov bsp_record(%rip), %rdi
    test %rdi, %rdi
    jz fatal
    call set_core_pointer
    mov $0x802, %ecx
    rdmsr
    mov bsp_record(%rip), %rdi
    cmp 16(%rdi), %eax
    jne fatal

#ifdef FLYOLOGY_EXCEPTIONS
    call flyology_exception_initialize
#endif
    call adainit
#ifdef FLYOLOGY_EXCEPTIONS
#ifndef FLYOLOGY_TASKING
    call _ada_exception_probe
    lea exception_pass(%rip), %rdi
    call serial_puts_locked
#endif
#endif
#ifdef FLYOLOGY_TASKING
    lea ada_elaboration_pass(%rip), %rdi
    call serial_puts_locked
#endif
#ifdef FLYOLOGY_INTERRUPTS
#ifndef FLYOLOGY_TASKING
    call _ada_flyology_interrupt_checkpoint
#endif
#else
#if defined(FLYOLOGY_EXCEPTIONS) && !defined(FLYOLOGY_TASKING)
    call adafinal
#else
    call _ada_flyology_boot_checkpoint
    call adafinal
#endif
#endif
#ifndef FLYOLOGY_TASKING
    lea ada_pass(%rip), %rdi
    call serial_puts_locked
#endif

    xor %edi, %edi
    call print_online
    mov bsp_record(%rip), %rax
    movq $1, 40(%rax)
    lock incl online_count(%rip)

    xor %ebx, %ebx
release_loop:
    cmp %r13, %rbx
    jae wait_online
    mov (%r14,%rbx,8), %rdi
    cmp %r15, %rdi
    je release_next
    lea ap_entry(%rip), %rax
    mov %rax, 16(%rdi)
release_next:
    inc %rbx
    jmp release_loop

wait_online:
    pause
    mov online_count(%rip), %eax
    cmp %r13d, %eax
    jne wait_online
#ifdef FLYOLOGY_INTERRUPTS
    call initialize_task_fp
    call initialize_x2apic
    call initialize_cpu_tables
#ifdef FLYOLOGY_TASKING
    xor %edi, %edi
    call flyology_kernel_prepare_environment
#else
    sti
    call flyology_interrupts_core_entry
    cli
    call interrupt_idle_reschedule_test
    lock incl interrupt_complete_count(%rip)
#endif
wait_m2_complete:
#ifdef FLYOLOGY_TASKING
    pause
    mov dispatcher_ready_count(%rip), %eax
    cmp %r13d, %eax
    jne wait_m2_complete
    sti
    call _ada_flyology_conformance
    lea ada_pass(%rip), %rdi
    call serial_puts_locked
    lea tasking_boot_pass(%rip), %rdi
    call serial_puts_locked
    call adafinal
    cli
    call flyology_kernel_environment_complete
    jmp fatal
#else
    pause
    mov interrupt_complete_count(%rip), %eax
    cmp %r13d, %eax
    jne wait_m2_complete
    lea interrupt_pass(%rip), %rdi
    call serial_puts_locked
    call adafinal
#endif
#else
    lea boot_pass(%rip), %rdi
    call serial_puts_locked
#endif
halt:
    hlt
    jmp halt

.type ap_entry, @function
ap_entry:
    cli
    cld
    call install_idt
    mov 24(%rdi), %rbx
    test %rbx, %rbx
    jz fatal
    mov 0(%rbx), %rax
    cmp $MAX_CORES, %rax
    jae fatal
    mov 32(%rbx), %rsp
    xor %ebp, %ebp
    mov %rbx, %rdi
    call set_core_pointer
    mov $0x802, %ecx
    rdmsr
    cmp 16(%rbx), %eax
    jne fatal
    mov 0(%rbx), %edi
    call print_online
    movq $1, 40(%rbx)
    lock incl online_count(%rip)
#ifdef FLYOLOGY_INTERRUPTS
    call initialize_task_fp
    call initialize_x2apic
    call initialize_cpu_tables
#ifdef FLYOLOGY_TASKING
    mov %gs:0, %rdi
    call flyology_kernel_prepare_ap
    jmp fatal
#else
    sti
    call flyology_interrupts_core_entry
    cli
    call interrupt_idle_reschedule_test
    lock incl interrupt_complete_count(%rip)
#endif
#endif
ap_halt:
    hlt
    jmp ap_halt

/* rdi = revision-zero memmap response, r15 = HHDM offset. */
.type validate_memmap, @function
validate_memmap:
    push %rax
    mov 8(%rdi), %rbp
    test %rbp, %rbp
    jz fatal
    cmp $256, %rbp
    ja fatal
    mov 16(%rdi), %r12
    test %r12, %r12
    jz fatal
    movb $0, memory_usable_found(%rip)
    xor %r14d, %r14d
1:
    cmp %rbp, %r14
    jae 4f
    mov (%r12,%r14,8), %r13
    test %r13, %r13
    jz fatal
    mov 0(%r13), %rdi
    mov 8(%r13), %rsi
    mov 16(%r13), %rdx
    mov %r15, %rcx
    call flyology_memory_entry_is_valid
    test %eax, %eax
    jz fatal
    xor %ebx, %ebx
2:
    cmp %r14, %rbx
    jae 3f
    mov (%r12,%rbx,8), %rax
    test %rax, %rax
    jz fatal
    mov 0(%r13), %rdi
    mov 8(%r13), %rsi
    mov 0(%rax), %rdx
    mov 8(%rax), %rcx
    call flyology_memory_entries_are_disjoint
    test %eax, %eax
    jz fatal
    inc %rbx
    jmp 2b
3:
    mov 16(%r13), %rax
    test %rax, %rax
    jnz 5f
    movb $1, memory_usable_found(%rip)
5:
    inc %r14
    jmp 1b
4:
    cmpb $0, memory_usable_found(%rip)
    jz fatal
    pop %rax
    ret

.type initialize_idt, @function
initialize_idt:
    lea idt_table(%rip), %rdi
    lea fatal_vector(%rip), %r8
    mov %cs, %dx
    mov $256, %ecx
1:
    mov %r8, %rax
    mov %ax, 0(%rdi)
    mov %dx, 2(%rdi)
    movb $0, 4(%rdi)
    movb $0x8e, 5(%rdi)
    shr $16, %rax
    mov %ax, 6(%rdi)
    mov %r8, %rax
    shr $32, %rax
    mov %eax, 8(%rdi)
    movl $0, 12(%rdi)
    add $16, %rdi
    loop 1b
    movw $(256 * 16 - 1), idt_descriptor(%rip)
    lea idt_table(%rip), %rax
    mov %rax, idt_descriptor + 2(%rip)
#ifdef FLYOLOGY_INTERRUPTS
    lea idt_table(%rip), %rsi
    lea interrupt_idt_table(%rip), %rdi
    mov $512, %ecx
    rep movsq
    movw $(256 * 16 - 1), interrupt_idt_descriptor(%rip)
    lea interrupt_idt_table(%rip), %rax
    mov %rax, interrupt_idt_descriptor + 2(%rip)
    lea interrupt_idt_table + TIMER_VECTOR * 16(%rip), %rdi
#else
    lea idt_table + TIMER_VECTOR * 16(%rip), %rdi
#endif
#ifdef FLYOLOGY_INTERRUPTS
    lea timer_vector(%rip), %r8
    mov %r8, %rax
    mov %ax, 0(%rdi)
    mov %dx, 2(%rdi)
    movb $0, 4(%rdi)
    movb $0x8e, 5(%rdi)
    shr $16, %rax
    mov %ax, 6(%rdi)
    mov %r8, %rax
    shr $32, %rax
    mov %eax, 8(%rdi)
    movl $0, 12(%rdi)
    lea interrupt_idt_table + RESCHEDULE_VECTOR * 16(%rip), %rdi
    lea reschedule_vector(%rip), %r8
    mov %r8, %rax
    mov %ax, 0(%rdi)
    mov %dx, 2(%rdi)
    movb $0, 4(%rdi)
    movb $0x8e, 5(%rdi)
    shr $16, %rax
    mov %ax, 6(%rdi)
    mov %r8, %rax
    shr $32, %rax
    mov %eax, 8(%rdi)
    movl $0, 12(%rdi)
    lea idt_table + IDT_TRANSITION_VECTOR * 16(%rip), %rdi
    lea idt_transition_vector(%rip), %r8
    mov %r8, %rax
    mov %ax, 0(%rdi)
    mov %dx, 2(%rdi)
    movb $0, 4(%rdi)
    movb $0x8e, 5(%rdi)
    shr $16, %rax
    mov %ax, 6(%rdi)
    mov %r8, %rax
    shr $32, %rax
    mov %eax, 8(%rdi)
    movl $0, 12(%rdi)
    lea interrupt_idt_table(%rip), %rdi
    mov $256, %ecx
2:
    movw $0x08, 2(%rdi)
    movb $1, 4(%rdi)
    add $16, %rdi
    loop 2b
#endif
    jmp install_idt

.type install_idt, @function
install_idt:
    lidt idt_descriptor(%rip)
    ret

fatal_vector:
    cli
    /* The minimal bootstrap IDT reports but does not resume an exception. */
    lea emergency_stack_end(%rip), %rsp
    movl $0, serial_lock(%rip)
    lea fail_marker(%rip), %rdi
    call serial_puts
    jmp halt

#ifdef FLYOLOGY_INTERRUPTS
.type idt_transition_vector, @function
idt_transition_vector:
    movq $1, %gs:104
    iretq

.type reschedule_vector, @function
reschedule_vector:
    pushq $RESCHEDULE_VECTOR
    jmp interrupt_interrupt_common

.type timer_vector, @function
timer_vector:
    pushq $TIMER_VECTOR

.type interrupt_interrupt_common, @function
interrupt_interrupt_common:
    cld
    push %rax
    push %rbx
    push %rcx
    push %rdx
    push %rsi
    push %rdi
    push %rbp
    push %r8
    push %r9
    push %r10
    push %r11
    push %r12
    push %r13
    push %r14
    push %r15

    mov %gs:0, %rax
    cmp $MAX_CORES, %rax
    jae fatal
    cmpq $255, %gs:112
    jae fatal
    incq %gs:112
    shl $8, %rax
    lea interrupt_frames(%rip), %r12
    add %rax, %r12
    mov %rsp, %rsi
    mov %r12, %rdi
    mov $15, %ecx
    rep movsq
    mov $0xc0000100, %ecx
    rdmsr
    shl $32, %rdx
    or %rdx, %rax
    mov %rax, 120(%r12)
    mov 128(%rsp), %rax
    mov %rax, 128(%r12)
    mov 136(%rsp), %rax
    mov %rax, 136(%r12)
    mov 144(%rsp), %rax
    mov %rax, 144(%r12)
    mov 152(%rsp), %rax
    mov %rax, 152(%r12)
    mov 160(%rsp), %rax
    mov %rax, 160(%r12)
    mov 120(%rsp), %rax
    mov %rax, 168(%r12)
    movq $0, 176(%r12)
    cmpq $0x08, 136(%r12)
    jne fatal
    cmpq $0x10, 160(%r12)
    jne fatal
    testq $2, 144(%r12)
    jz fatal
    mov 128(%r12), %rax
    mov %rax, %rdx
    shl $16, %rdx
    sar $16, %rdx
    cmp %rax, %rdx
    jne fatal
    mov 152(%r12), %rax
    test $7, %rax
    jnz fatal
    mov %rax, %rdx
    shl $16, %rdx
    sar $16, %rdx
    cmp %rax, %rdx
    jne fatal

    mov %gs:0, %rax
    shl $12, %rax
    lea xsave_areas(%rip), %rdi
    add %rax, %rdi
    mov %rdi, 184(%r12)
    mov $0x0d, %eax
    xor %ecx, %ecx
    cpuid
    test %ebx, %ebx
    jz fatal
    cmp $4096, %ebx
    ja fatal
    mov %rbx, 192(%r12)
    movq $3, 200(%r12)
    mov %cr2, %rax
    mov %rax, 208(%r12)
    mov $3, %eax
    xor %edx, %edx
    xsave64 (%rdi)
#ifndef FLYOLOGY_PREEMPTION
    /*
     * interrupt substrate runs the canary without context transfer, so this per-core flag
     * still identifies the interrupted execution.  preemption may preempt that task
     * and run another task on the same core; applying the old flag to the new
     * task would reject legitimate FP/SIMD state.  preemption instead validates the
     * complete task-owned state after its exact interrupt continuation
     * resumes in flyology_conformance_preemption_canary.
     */
    cmpq $0, %gs:80
    je 3f
    cmpw $0x027f, 0(%rdi)
    jne fatal
    cmpl $0x1f80, 24(%rdi)
    jne fatal
    mov interrupt_simd_canary(%rip), %rax
    cmp %rax, 160(%rdi)
    jne fatal
    mov interrupt_simd_canary + 8(%rip), %rax
    cmp %rax, 168(%rdi)
    jne fatal
    mov interrupt_simd_canary + 16(%rip), %rax
    cmp %rax, 400(%rdi)
    jne fatal
    mov interrupt_simd_canary + 24(%rip), %rax
    cmp %rax, 408(%rdi)
    jne fatal
3:
#endif

    mov 168(%r12), %rax
    cmp $RESCHEDULE_VECTOR, %rax
    jne 1f
    lock orq $1, %gs:72
    jmp 2f
1:
    cmp $TIMER_VECTOR, %rax
    jne fatal
    mov $0x832, %ecx
    mov $(0x10000 | TIMER_VECTOR), %eax
    xor %edx, %edx
    wrmsr
    lock orq $2, %gs:64
    lock incq %gs:48
    js fatal
    lock orq $2, %gs:72
    cmpq $0, %gs:88
    je 2f
    movq $1, %gs:96
2:
#ifdef FLYOLOGY_PREEMPTION
    xor %r13d, %r13d
    cmpq $0, %gs:88
    jne 6f
    mov %r12, %rdi
    mov %gs:0, %rsi
    sub $8, %rsp
    call flyology_kernel_interrupt_dispatch
    add $8, %rsp
    mov %rax, %r13
6:
#endif
    mov $0x80b, %ecx
    xor %eax, %eax
    xor %edx, %edx
    wrmsr
    cmpq $0, %gs:112
    je fatal
    decq %gs:112
#ifdef FLYOLOGY_PREEMPTION
    test %r13, %r13
    jz 7f
    mov %r13, %rdi
    jmp flyology_context_restore_from_interrupt
7:
#endif
    mov 184(%r12), %rdi
    mov $3, %eax
    xor %edx, %edx
    xrstor64 (%rdi)
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %r11
    pop %r10
    pop %r9
    pop %r8
    pop %rbp
    pop %rdi
    pop %rsi
    pop %rdx
    pop %rcx
    pop %rbx
    pop %rax
    add $8, %rsp
    iretq
#endif

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
.type __gnat_last_chance_handler, @function
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
    cli
    movl $0, serial_lock(%rip)
#ifdef FLYOLOGY_EXCEPTIONS
    push %rdi
    lea exception_detail(%rip), %rdi
    call serial_puts
    pop %rdi
    call serial_puts
    mov $'\n', %edi
    call serial_putc
#endif
    lea last_chance_marker(%rip), %rdi
    call serial_puts
    jmp halt

.type set_core_pointer, @function
set_core_pointer:
    mov %rdi, %rax
    mov %rdi, %rdx
    shr $32, %rdx
    mov $0xc0000101, %ecx
    wrmsr
    ret

#ifdef FLYOLOGY_EXCEPTIONS
.type initialize_exception_fp, @function
initialize_exception_fp:
    push %rbx
    mov $1, %eax
    cpuid
    bt $24, %edx
    jnc fatal
    bt $25, %edx
    jnc fatal
    bt $26, %ecx
    jnc fatal
    mov %cr0, %rax
    and $-13, %rax
    or $2, %rax
    mov %rax, %cr0
    mov %cr4, %rax
    or $0x40600, %rax
    mov %rax, %cr4
    xor %ecx, %ecx
    mov $3, %eax
    xor %edx, %edx
    xsetbv
    fninit
    sub $16, %rsp
    movl $0x1f80, (%rsp)
    ldmxcsr (%rsp)
    add $16, %rsp
    pop %rbx
    ret
#endif

#ifdef FLYOLOGY_INTERRUPTS
.type initialize_task_fp, @function
initialize_task_fp:
    push %rbx
    mov $1, %eax
    cpuid
    bt $24, %edx
    jnc fatal
    bt $25, %edx
    jnc fatal
    bt $26, %ecx
    jnc fatal
    mov %cr0, %rax
    and $-13, %rax
    or $2, %rax
    mov %rax, %cr0
    mov %cr4, %rax
    or $0x40600, %rax
    mov %rax, %cr4
    xor %ecx, %ecx
    mov $3, %eax
    xor %edx, %edx
    xsetbv
    fninit
    sub $16, %rsp
    movl $0x1f80, (%rsp)
    ldmxcsr (%rsp)
    add $16, %rsp
    pop %rbx
    ret

.type initialize_x2apic, @function
initialize_x2apic:
    mov $0x832, %ecx
    rdmsr
    or $0x10000, %eax
    wrmsr
    mov $0x835, %ecx
    rdmsr
    or $0x10000, %eax
    wrmsr
    mov $0x836, %ecx
    rdmsr
    or $0x10000, %eax
    wrmsr
    mov $0x837, %ecx
    rdmsr
    or $0x10000, %eax
    wrmsr
    mov $0x808, %ecx
    xor %eax, %eax
    xor %edx, %edx
    wrmsr
    mov $0x80f, %ecx
    rdmsr
    and $-512, %eax
    or $0x1ff, %eax
    wrmsr
    ret

/* Install a private GDT, TSS, and IST1 stack for the current dense core. */
.type initialize_cpu_tables, @function
initialize_cpu_tables:
    push %rbx
    push %r12
    mov %gs:0, %r12
    cmp $MAX_CORES, %r12
    jae fatal

    lea tss_records(%rip), %rbx
    mov %r12, %rax
    shl $7, %rax
    add %rax, %rbx
    lea exception_stacks(%rip), %rax
    mov %r12, %rcx
    inc %rcx
    shl $EXCEPTION_STACK_SHIFT, %rcx
    add %rcx, %rax
    mov %rax, 4(%rbx)
    mov %rax, 36(%rbx)
    movw $104, 102(%rbx)

    lea gdt_tables(%rip), %rdi
    mov %r12, %rax
    shl $GDT_SHIFT, %rax
    add %rax, %rdi
    movq $0, 0(%rdi)
    movabs $0x00af9a000000ffff, %rax
    mov %rax, 8(%rdi)
    movabs $0x00cf92000000ffff, %rax
    mov %rax, 16(%rdi)
    movw $103, 24(%rdi)
    mov %rbx, %rax
    movw %ax, 26(%rdi)
    shr $16, %rax
    movb %al, 28(%rdi)
    movb $0x89, 29(%rdi)
    movb $0, 30(%rdi)
    mov %rbx, %rax
    shr $24, %rax
    movb %al, 31(%rdi)
    mov %rbx, %rax
    shr $32, %rax
    movl %eax, 32(%rdi)
    movl $0, 36(%rdi)
    /* Keep the bootstrap IDT's live selector valid under the private GDT. */
    mov %cs, %dx
    test $4, %dx
    jnz fatal
    movzwq %dx, %rcx
    and $-8, %rcx
    test %rcx, %rcx
    jz fatal
    cmp $GDT_DESCRIPTOR_OFFSET - 8, %rcx
    ja fatal
    cmp $8, %rcx
    je 2f
    cmp $16, %rcx
    jb 1f
    cmp $39, %rcx
    jbe fatal
1:
    movabs $0x00af9a000000ffff, %rax
    mov %rax, 0(%rdi,%rcx)
2:
    movw $GDT_LIMIT, GDT_DESCRIPTOR_OFFSET(%rdi)
    lea 0(%rdi), %rax
    mov %rax, GDT_DESCRIPTOR_OFFSET + 2(%rdi)
    lgdt GDT_DESCRIPTOR_OFFSET(%rdi)
    pushq $0x08
    lea 3f(%rip), %rax
    push %rax
    lretq
3:
    mov $0x10, %eax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    int $IDT_TRANSITION_VECTOR
    cmpq $1, %gs:104
    jne fatal
    mov $0x18, %eax
    ltr %ax
    lidt interrupt_idt_descriptor(%rip)
    pop %r12
    pop %rbx
    ret

.type interrupt_arm_task_timer, @function
interrupt_arm_task_timer:
    andq $-3, %gs:72
    mov $0x83e, %ecx
    mov $3, %eax
    xor %edx, %edx
    wrmsr
    mov $0x832, %ecx
    mov $TIMER_VECTOR, %eax
    xor %edx, %edx
    wrmsr
    mov $0x838, %ecx
    mov $100000, %eax
    xor %edx, %edx
    wrmsr
    ret

.global flyology_interrupts_wait_for_timer_request
.type flyology_interrupts_wait_for_timer_request, @function
flyology_interrupts_wait_for_timer_request:
    sub $24, %rsp
    movw $0x027f, 0(%rsp)
    fldcw 0(%rsp)
    movq $1, %gs:80
    movdqa interrupt_simd_canary(%rip), %xmm0
    movdqa interrupt_simd_canary + 16(%rip), %xmm15
    call interrupt_arm_task_timer
    movabs $0x1122334455667788, %r8
    movabs $0x8877665544332211, %r9
    movabs $0x5aa55aa5a55aa55a, %r10
    movabs $0xa55aa55a5aa55aa5, %r11
1:
    testq $2, %gs:72
    jnz 2f
    pause
    jmp 1b
2:
    movabs $0x1122334455667788, %rax
    cmp %rax, %r8
    jne fatal
    movabs $0x8877665544332211, %rax
    cmp %rax, %r9
    jne fatal
    movabs $0x5aa55aa5a55aa55a, %rax
    cmp %rax, %r10
    jne fatal
    movabs $0xa55aa55a5aa55aa5, %rax
    cmp %rax, %r11
    jne fatal
    pcmpeqb interrupt_simd_canary(%rip), %xmm0
    pmovmskb %xmm0, %eax
    cmp $0xffff, %eax
    jne fatal
    pcmpeqb interrupt_simd_canary + 16(%rip), %xmm15
    pmovmskb %xmm15, %eax
    cmp $0xffff, %eax
    jne fatal
    fnstcw 2(%rsp)
    cmpw $0x027f, 2(%rsp)
    jne fatal
    movw $0x037f, 4(%rsp)
    fldcw 4(%rsp)
    movq $0, %gs:80
    add $24, %rsp
    ret

.global flyology_interrupts_acknowledge_requests
.type flyology_interrupts_acknowledge_requests, @function
flyology_interrupts_acknowledge_requests:
    mov %gs:48, %rdx
    mov %rdx, %gs:56
    mov %gs:64, %rax
    ret

.global flyology_interrupts_parallel_task_barrier
.type flyology_interrupts_parallel_task_barrier, @function
flyology_interrupts_parallel_task_barrier:
    lock incl interrupt_task_barrier_count(%rip)
1:
    mov interrupt_task_barrier_count(%rip), %eax
    cmp cpu_count(%rip), %eax
    je 2f
    pause
    jmp 1b
2:
    ret

.global flyology_interrupts_arm_deferred_timer
.type flyology_interrupts_arm_deferred_timer, @function
flyology_interrupts_arm_deferred_timer:
    andq $-3, %gs:72
    call interrupt_arm_task_timer
1:
    testq $2, %gs:72
    jnz 2f
    pause
    jmp 1b
2:
    ret

.global flyology_interrupts_consume_deferred
.type flyology_interrupts_consume_deferred, @function
flyology_interrupts_consume_deferred:
    xor %eax, %eax
    xchg %rax, %gs:96
    ret

.global flyology_platform_disable_dispatch
.type flyology_platform_disable_dispatch, @function
flyology_platform_disable_dispatch:
    cli
    ret

.global flyology_platform_enable_dispatch
.type flyology_platform_enable_dispatch, @function
flyology_platform_enable_dispatch:
    sti
    ret

.type interrupt_idle_reschedule_test, @function
interrupt_idle_reschedule_test:
    push %rbx
    push %r12
    movq $0, %gs:72
    lock incl interrupt_idle_ready_count(%rip)
    mov %gs:0, %ebx
    test %ebx, %ebx
    jnz 3f
1:
    pause
    mov interrupt_idle_ready_count(%rip), %eax
    cmp cpu_count(%rip), %eax
    jne 1b
    xor %r12d, %r12d
2:
    cmp cpu_count(%rip), %r12d
    jae 3f
    lea core_records(%rip), %rax
    mov %r12, %rdx
    shl $CORE_RECORD_SHIFT, %rdx
    add %rdx, %rax
    lock orq $1, 64(%rax)
    lock incq 48(%rax)
    js fatal
    mov 16(%rax), %edx
    mov $(0x4000 | RESCHEDULE_VECTOR), %eax
    mov $0x830, %ecx
    wrmsr
    inc %r12d
    jmp 2b
3:
    testq $1, %gs:72
    jnz 4f
    sti
    hlt
    cli
    jmp 3b
4:
    call flyology_interrupts_acknowledge_requests
    test $1, %eax
    jz fatal
    mov %ebx, %edi
    call interrupt_report_ipi_pass
    andq $-3, %gs:72
    mov $0x83e, %ecx
    mov $3, %eax
    xor %edx, %edx
    wrmsr
    mov $0x832, %ecx
    mov $TIMER_VECTOR, %eax
    xor %edx, %edx
    wrmsr
    mov $0x838, %ecx
    mov $1000000, %eax
    xor %edx, %edx
    wrmsr
5:
    testq $2, %gs:72
    jnz 6f
    sti
    hlt
    cli
    jmp 5b
6:
    call flyology_interrupts_acknowledge_requests
    test $2, %eax
    jz fatal
    mov %ebx, %edi
    call interrupt_report_timer_pass
    pop %r12
    pop %rbx
    ret

.type interrupt_report_ipi_pass, @function
interrupt_report_ipi_pass:
    push %rbx
    mov %edi, %ebx
    call serial_lock_acquire
    lea interrupt_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea interrupt_ipi_suffix(%rip), %rdi
    call serial_puts
    call serial_lock_release
    pop %rbx
    ret

.type interrupt_report_timer_pass, @function
interrupt_report_timer_pass:
    push %rbx
    mov %edi, %ebx
    call serial_lock_acquire
    lea interrupt_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea interrupt_timer_suffix(%rip), %rdi
    call serial_puts
    call serial_lock_release
    pop %rbx
    ret

.global flyology_current_core
.type flyology_current_core, @function
flyology_current_core:
    mov %gs:0, %rax
    ret

#ifdef FLYOLOGY_TASKING
.weak adafinal
.type adafinal, @function
adafinal:
    ret

.global flyology_platform_boot_cpu_count
.type flyology_platform_boot_cpu_count, @function
flyology_platform_boot_cpu_count:
    mov cpu_count(%rip), %eax
    ret

.global flyology_platform_dispatcher_ready
.type flyology_platform_dispatcher_ready, @function
flyology_platform_dispatcher_ready:
    lock incl dispatcher_ready_count(%rip)
    ret

.global flyology_platform_prepare_idle
.type flyology_platform_prepare_idle, @function
flyology_platform_prepare_idle:
    movq %gs:48, %rax
    movq %rax, %gs:56
    ret

.global flyology_platform_idle
.type flyology_platform_idle, @function
flyology_platform_idle:
    cli
    movq %gs:48, %rax
    cmpq %gs:56, %rax
    jne 1f
    sti
    hlt
    ret
1:
    sti
    ret

.global flyology_platform_kick_core
.type flyology_platform_kick_core, @function
flyology_platform_kick_core:
    cmp cpu_count(%rip), %edi
    jae fatal
    lea core_records(%rip), %rax
    mov %edi, %edx
    shl $CORE_RECORD_SHIFT, %rdx
    add %rdx, %rax
    lock orq $1, 64(%rax)
    lock incq 48(%rax)
    js fatal
    mov 16(%rax), %edx
    mov $(0x4000 | RESCHEDULE_VECTOR), %eax
    mov $0x830, %ecx
    wrmsr
    ret

.global flyology_conformance_validate_environment_stack
.type flyology_conformance_validate_environment_stack, @function
flyology_conformance_validate_environment_stack:
    cmp cpu_count(%rip), %rdi
    jae fatal
    lea core_records(%rip), %rax
    mov %rdi, %rcx
    shl $CORE_RECORD_SHIFT, %rcx
    add %rcx, %rax
    mov 32(%rax), %rdx
    mov %rdx, %rcx
    sub $(1 << STACK_SHIFT), %rcx
    xor %eax, %eax
    cmp %rcx, %rsi
    jb 1f
    cmp %rdx, %rsi
    jae 1f
    mov $1, %eax
1:
    ret

.global flyology_conformance_report_ordinary_pass
.type flyology_conformance_report_ordinary_pass, @function
flyology_conformance_report_ordinary_pass:
    lea tasking_ordinary_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_specific_pass
.type flyology_conformance_report_specific_pass, @function
flyology_conformance_report_specific_pass:
    lea tasking_specific_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_parallel_pass
.type flyology_conformance_report_parallel_pass, @function
flyology_conformance_report_parallel_pass:
    lea tasking_parallel_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_auto_master_pass
.type flyology_conformance_report_auto_master_pass, @function
flyology_conformance_report_auto_master_pass:
    lea tasking_auto_master_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_reclamation_pass
.type flyology_conformance_report_reclamation_pass, @function
flyology_conformance_report_reclamation_pass:
    lea rts_reclamation_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_delay_pass
.type flyology_conformance_report_delay_pass, @function
flyology_conformance_report_delay_pass:
    lea rts_delay_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_absolute_delay_pass
.type flyology_conformance_report_absolute_delay_pass, @function
flyology_conformance_report_absolute_delay_pass:
    lea rts_absolute_delay_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_protected_pass
.type flyology_conformance_report_protected_pass, @function
flyology_conformance_report_protected_pass:
    lea rts_protected_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_protected_entry_pass
.type flyology_conformance_report_protected_entry_pass, @function
flyology_conformance_report_protected_entry_pass:
    lea rts_protected_entry_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_finalization_pass
.type flyology_conformance_report_finalization_pass, @function
flyology_conformance_report_finalization_pass:
    lea rts_finalization_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_rendezvous_pass
.type flyology_conformance_report_rendezvous_pass, @function
flyology_conformance_report_rendezvous_pass:
    lea rts_rendezvous_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_exceptional_sync_pass
.type flyology_conformance_report_exceptional_sync_pass, @function
flyology_conformance_report_exceptional_sync_pass:
    lea rts_exceptional_sync_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_exceptional_protected_immediate_pass
.type flyology_conformance_report_exceptional_protected_immediate_pass, @function
flyology_conformance_report_exceptional_protected_immediate_pass:
    lea rts_exceptional_protected_immediate_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_exceptional_protected_queued_pass
.type flyology_conformance_report_exceptional_protected_queued_pass, @function
flyology_conformance_report_exceptional_protected_queued_pass:
    lea rts_exceptional_protected_queued_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_exception_abort_protected_pass
.type flyology_conformance_report_exception_abort_protected_pass, @function
flyology_conformance_report_exception_abort_protected_pass:
    lea rts_exception_abort_protected_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_exceptional_rendezvous_pass
.type flyology_conformance_report_exceptional_rendezvous_pass, @function
flyology_conformance_report_exceptional_rendezvous_pass:
    lea rts_exceptional_rendezvous_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_exception_abort_pass
.type flyology_conformance_report_exception_abort_pass, @function
flyology_conformance_report_exception_abort_pass:
    lea rts_exception_abort_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_unactivated_cleanup_pass
.type flyology_conformance_report_unactivated_cleanup_pass, @function
flyology_conformance_report_unactivated_cleanup_pass:
    lea rts_unactivated_cleanup_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_allocator_pass
.type flyology_conformance_report_allocator_pass, @function
flyology_conformance_report_allocator_pass:
    lea rts_allocator_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_priority_pass
.type flyology_conformance_report_priority_pass, @function
flyology_conformance_report_priority_pass:
    lea rts_priority_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_ceiling_pass
.type flyology_conformance_report_ceiling_pass, @function
flyology_conformance_report_ceiling_pass:
    lea rts_ceiling_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_conditional_pass
.type flyology_conformance_report_conditional_pass, @function
flyology_conformance_report_conditional_pass:
    lea rts_conditional_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_timed_entry_pass
.type flyology_conformance_report_timed_entry_pass, @function
flyology_conformance_report_timed_entry_pass:
    lea rts_timed_entry_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_dynamic_task_pass
.type flyology_conformance_report_dynamic_task_pass, @function
flyology_conformance_report_dynamic_task_pass:
    lea rts_dynamic_task_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_free_task_pass
.type flyology_conformance_report_free_task_pass, @function
flyology_conformance_report_free_task_pass:
    lea rts_free_task_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_free_wait_pass
.type flyology_conformance_report_free_wait_pass, @function
flyology_conformance_report_free_wait_pass:
    lea rts_free_wait_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_free_abort_race_pass
.type flyology_conformance_report_free_abort_race_pass, @function
flyology_conformance_report_free_abort_race_pass:
    lea rts_free_abort_race_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_selective_wait_pass
.type flyology_conformance_report_selective_wait_pass, @function
flyology_conformance_report_selective_wait_pass:
    lea rts_selective_wait_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_terminate_alternative_pass
.type flyology_conformance_report_terminate_alternative_pass, @function
flyology_conformance_report_terminate_alternative_pass:
    lea rts_terminate_alternative_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_abort_pass
.type flyology_conformance_report_abort_pass, @function
flyology_conformance_report_abort_pass:
    lea rts_abort_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_multi_abort_pass
.type flyology_conformance_report_multi_abort_pass, @function
flyology_conformance_report_multi_abort_pass:
    lea rts_multi_abort_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_dependent_abort_pass
.type flyology_conformance_report_dependent_abort_pass, @function
flyology_conformance_report_dependent_abort_pass:
    lea rts_dependent_abort_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_abort_rendezvous_pass
.type flyology_conformance_report_abort_rendezvous_pass, @function
flyology_conformance_report_abort_rendezvous_pass:
    lea rts_abort_rendezvous_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_abort_timeout_pass
.type flyology_conformance_report_abort_timeout_pass, @function
flyology_conformance_report_abort_timeout_pass:
    lea rts_abort_timeout_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_abort_accepted_pass
.type flyology_conformance_report_abort_accepted_pass, @function
flyology_conformance_report_abort_accepted_pass:
    lea rts_abort_accepted_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_abort_protected_pass
.type flyology_conformance_report_abort_protected_pass, @function
flyology_conformance_report_abort_protected_pass:
    lea rts_abort_protected_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_collision_stress_pass
.type flyology_conformance_report_collision_stress_pass, @function
flyology_conformance_report_collision_stress_pass:
    lea rts_collision_stress_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_fifo_preemption_pass
.type flyology_conformance_report_fifo_preemption_pass, @function
flyology_conformance_report_fifo_preemption_pass:
    lea preemption_fifo_preemption_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_preemption_canary
.type flyology_conformance_preemption_canary, @function
flyology_conformance_preemption_canary:
    pushfq
    push %rbx
    push %rbp
    push %r12
    push %r13
    push %r14
    push %r15
    push %rdi
    sub $24, %rsp
    fnstcw 0(%rsp)
    stmxcsr 4(%rsp)
    mov %rsp, %rax
    mov %rax, 8(%rsp)
    movl $0x1f80, 16(%rsp)
    ldmxcsr 16(%rsp)
    movw $0x027f, 20(%rsp)
    fldcw 20(%rsp)
    movq $1, %gs:80

    movdqa interrupt_simd_canary(%rip), %xmm0
    movdqa interrupt_simd_canary(%rip), %xmm1
    movdqa interrupt_simd_canary(%rip), %xmm2
    movdqa interrupt_simd_canary(%rip), %xmm3
    movdqa interrupt_simd_canary(%rip), %xmm4
    movdqa interrupt_simd_canary(%rip), %xmm5
    movdqa interrupt_simd_canary(%rip), %xmm6
    movdqa interrupt_simd_canary(%rip), %xmm7
    movdqa interrupt_simd_canary(%rip), %xmm8
    movdqa interrupt_simd_canary(%rip), %xmm9
    movdqa interrupt_simd_canary(%rip), %xmm10
    movdqa interrupt_simd_canary(%rip), %xmm11
    movdqa interrupt_simd_canary(%rip), %xmm12
    movdqa interrupt_simd_canary(%rip), %xmm13
    movdqa interrupt_simd_canary(%rip), %xmm14
    movdqa interrupt_simd_canary + 16(%rip), %xmm15

    movabs $0x1111111111111111, %rax
    movabs $0x2222222222222222, %rbx
    movabs $0x3333333333333333, %rcx
    movabs $0x4444444444444444, %rdx
    movabs $0x5555555555555555, %rsi
    movabs $0x6666666666666666, %rbp
    movabs $0x8888888888888888, %r8
    movabs $0x9999999999999999, %r9
    movabs $0xaaaaaaaaaaaaaaaa, %r10
    movabs $0xbbbbbbbbbbbbbbbb, %r11
    movabs $0xcccccccccccccccc, %r12
    movabs $0xdddddddddddddddd, %r13
    movabs $0xeeeeeeeeeeeeeeee, %r14
    movabs $0xf0f0f0f0f0f0f0f0, %r15
    /*
     * Seed arithmetic status plus DF while retaining IF.  Interrupt entry
     * executes CLD before calling Ada, while the hardware frame must retain
     * this exact interrupted value for the eventual IRETQ resume.
     */
    pushfq
    pop %rcx
    andq $-3286, %rcx
    orq $0x491, %rcx
    push %rcx
    popfq
1:
    movzbq (%rdi), %rcx
    jrcxz 1b

    pushfq
    pop %rcx
    andl $0xcd5, %ecx
    cmpl $0x491, %ecx
    jne preemption_canary_status_fatal

    cmp 24(%rsp), %rdi
    jne preemption_canary_gpr_fatal
    cmp %rsp, 8(%rsp)
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 0(%rip), %rax
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 8(%rip), %rbx
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 24(%rip), %rdx
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 32(%rip), %rsi
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 40(%rip), %rbp
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 48(%rip), %r8
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 56(%rip), %r9
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 64(%rip), %r10
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 72(%rip), %r11
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 80(%rip), %r12
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 88(%rip), %r13
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 96(%rip), %r14
    jne preemption_canary_gpr_fatal
    cmp preemption_gpr_canaries + 104(%rip), %r15
    jne preemption_canary_gpr_fatal

.macro preemption_check_xmm register, expected
    pcmpeqb \expected(%rip), \register
    pmovmskb \register, %eax
    cmp $0xffff, %eax
    jne preemption_canary_simd_fatal
.endm
    preemption_check_xmm %xmm0, interrupt_simd_canary
    preemption_check_xmm %xmm1, interrupt_simd_canary
    preemption_check_xmm %xmm2, interrupt_simd_canary
    preemption_check_xmm %xmm3, interrupt_simd_canary
    preemption_check_xmm %xmm4, interrupt_simd_canary
    preemption_check_xmm %xmm5, interrupt_simd_canary
    preemption_check_xmm %xmm6, interrupt_simd_canary
    preemption_check_xmm %xmm7, interrupt_simd_canary
    preemption_check_xmm %xmm8, interrupt_simd_canary
    preemption_check_xmm %xmm9, interrupt_simd_canary
    preemption_check_xmm %xmm10, interrupt_simd_canary
    preemption_check_xmm %xmm11, interrupt_simd_canary
    preemption_check_xmm %xmm12, interrupt_simd_canary
    preemption_check_xmm %xmm13, interrupt_simd_canary
    preemption_check_xmm %xmm14, interrupt_simd_canary
    preemption_check_xmm %xmm15, interrupt_simd_canary + 16
.purgem preemption_check_xmm

    fnstcw 20(%rsp)
    cmpw $0x027f, 20(%rsp)
    jne preemption_canary_fp_fatal
    stmxcsr 16(%rsp)
    cmpl $0x1f80, 16(%rsp)
    jne preemption_canary_fp_fatal
    movq $0, %gs:80
    fldcw 0(%rsp)
    ldmxcsr 4(%rsp)
    add $24, %rsp
    pop %rdi
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbp
    pop %rbx
    popfq
    ret

preemption_canary_status_fatal:
    cld
    lea preemption_canary_status_failure(%rip), %rdi
    call serial_puts_locked
    jmp fatal
preemption_canary_gpr_fatal:
    cld
    lea preemption_canary_gpr_failure(%rip), %rdi
    call serial_puts_locked
    jmp fatal
preemption_canary_simd_fatal:
    cld
    lea preemption_canary_simd_failure(%rip), %rdi
    call serial_puts_locked
    jmp fatal
preemption_canary_fp_fatal:
    cld
    lea preemption_canary_fp_failure(%rip), %rdi
    call serial_puts_locked
    jmp fatal

.global flyology_conformance_report_round_robin_pass
.type flyology_conformance_report_round_robin_pass, @function
flyology_conformance_report_round_robin_pass:
    lea preemption_round_robin_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_remote_preemption_pass
.type flyology_conformance_report_remote_preemption_pass, @function
flyology_conformance_report_remote_preemption_pass:
    lea preemption_remote_preemption_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_all_core_preemption_pass
.type flyology_conformance_report_all_core_preemption_pass, @function
flyology_conformance_report_all_core_preemption_pass:
    lea preemption_all_core_preemption_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_fifo_no_rotation_pass
.type flyology_conformance_report_fifo_no_rotation_pass, @function
flyology_conformance_report_fifo_no_rotation_pass:
    lea preemption_fifo_no_rotation_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_priority_requeue_pass
.type flyology_conformance_report_priority_requeue_pass, @function
flyology_conformance_report_priority_requeue_pass:
    lea preemption_priority_requeue_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_nonblocking_ingress_pass
.type flyology_conformance_report_nonblocking_ingress_pass, @function
flyology_conformance_report_nonblocking_ingress_pass:
    lea preemption_nonblocking_ingress_pass(%rip), %rdi
    jmp serial_puts_locked

#ifdef FLYOLOGY_DOMAINS
.global flyology_conformance_report_layout_pass
.type flyology_conformance_report_layout_pass, @function
flyology_conformance_report_layout_pass:
    lea domain_layout_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_query_pass
.type flyology_conformance_report_query_pass, @function
flyology_conformance_report_query_pass:
    lea domain_query_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_inheritance_pass
.type flyology_conformance_report_inheritance_pass, @function
flyology_conformance_report_inheritance_pass:
    lea domain_inheritance_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_heterogeneous_pass
.type flyology_conformance_report_heterogeneous_pass, @function
flyology_conformance_report_heterogeneous_pass:
    lea domain_heterogeneous_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_all_core_pass
.type flyology_conformance_report_all_core_pass, @function
flyology_conformance_report_all_core_pass:
    lea domain_all_core_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_all_core_start_failure
.type flyology_conformance_report_all_core_start_failure, @function
flyology_conformance_report_all_core_start_failure:
    lea domain_all_core_start_failure(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_all_core_done_failure
.type flyology_conformance_report_all_core_done_failure, @function
flyology_conformance_report_all_core_done_failure:
    lea domain_all_core_done_failure(%rip), %rdi
    jmp serial_puts_locked
#endif

.global flyology_conformance_report_master_pass
.type flyology_conformance_report_master_pass, @function
flyology_conformance_report_master_pass:
    lea tasking_master_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_report_stack_pass
.type flyology_conformance_report_stack_pass, @function
flyology_conformance_report_stack_pass:
    lea tasking_stack_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_conformance_parallel_barrier
.type flyology_conformance_parallel_barrier, @function
flyology_conformance_parallel_barrier:
    test %edi, %edi
    jz fatal
    mov %edi, %eax
    imul cpu_count(%rip), %eax
    lock incl tasking_parallel_barrier_count(%rip)
1:
    cmp tasking_parallel_barrier_count(%rip), %eax
    je 2f
    pause
    jmp 1b
2:
    ret

.global flyology_platform_read_clock
.type flyology_platform_read_clock, @function
flyology_platform_read_clock:
    lfence
    rdtsc
    shl $32, %rdx
    or %rdx, %rax
    lfence
    ret

.global flyology_platform_clock_frequency
.type flyology_platform_clock_frequency, @function
flyology_platform_clock_frequency:
    mov $1000000000, %eax
    ret

.type rts_calibrate_apic_timer, @function
rts_calibrate_apic_timer:
    mov $0x832, %ecx
    mov $(0x10000 | TIMER_VECTOR), %eax
    xor %edx, %edx
    wrmsr
    mov $0x83e, %ecx
    mov $3, %eax
    xor %edx, %edx
    wrmsr
    mov $0x838, %ecx
    mov $0xffffffff, %eax
    xor %edx, %edx
    wrmsr
    call flyology_platform_read_clock
    mov %rax, %r8
1:
    mov $0x839, %ecx
    rdmsr
    mov $0xffffffff, %r9d
    sub %eax, %r9d
    cmp $100000, %r9d
    jb 1b
    call flyology_platform_read_clock
    sub %r8, %rax
    jz fatal
    mov %rax, %r10
    mov %r9, %rax
    mov $1000000000, %ecx
    mul %rcx
    div %r10
    cmp $1000000, %rax
    jb fatal
    cmp $1000000000, %rax
    ja fatal
    ret

.global flyology_platform_cancel_timer
.type flyology_platform_cancel_timer, @function
flyology_platform_cancel_timer:
    mov $0x832, %ecx
    mov $(0x10000 | TIMER_VECTOR), %eax
    xor %edx, %edx
    wrmsr
    mov $0x838, %ecx
    xor %eax, %eax
    xor %edx, %edx
    wrmsr
    ret

.global flyology_platform_program_timer
.type flyology_platform_program_timer, @function
flyology_platform_program_timer:
    push %rbx
    push %r12
    push %r13
    mov %rdi, %r12
    call flyology_platform_read_clock
    cmp %rax, %r12
    jbe 1f
    sub %rax, %r12
    jmp 2f
1:
    mov $1, %r12
2:
    mov %gs:0, %rbx
    lea rts_apic_rates(%rip), %r13
    mov (%r13,%rbx,8), %r11
    test %r11, %r11
    jnz 3f
    call rts_calibrate_apic_timer
    mov %rax, %r11
    mov %rax, (%r13,%rbx,8)
3:
    mov %r12, %rax
    mul %r11
    add $999999999, %rax
    adc $0, %rdx
    mov $1000000000, %ecx
    cmp %rcx, %rdx
    jae 4f
    div %rcx
    test %rax, %rax
    jnz 5f
    mov $1, %eax
    jmp 5f
4:
    mov $0xffffffff, %eax
5:
    mov $0xffffffff, %r10d
    cmp %r10, %rax
    cmova %r10, %rax
    mov %eax, %r12d
    mov $0x83e, %ecx
    mov $3, %eax
    xor %edx, %edx
    wrmsr
    mov $0x832, %ecx
    mov $TIMER_VECTOR, %eax
    xor %edx, %edx
    wrmsr
    mov $0x838, %ecx
    mov %r12d, %eax
    xor %edx, %edx
    wrmsr
    pop %r13
    pop %r12
    pop %rbx
    ret

.global flyology_platform_retry_interrupt
.type flyology_platform_retry_interrupt, @function
flyology_platform_retry_interrupt:
    /* A short local one-shot preserves ingress when the ISR cannot take the
       RTS lock without waiting.  The pending request epoch remains the
       correctness state; this timer is only the bounded retry prompt. */
    incq %gs:CORE_PREEMPTION_RETRY_COUNT
    jz fatal
    mov $0x83e, %ecx
    mov $3, %eax
    xor %edx, %edx
    wrmsr
    mov $0x832, %ecx
    mov $TIMER_VECTOR, %eax
    xor %edx, %edx
    wrmsr
    mov $0x838, %ecx
    mov $10000, %eax
    xor %edx, %edx
    wrmsr
    ret

.global flyology_platform_retry_count
.type flyology_platform_retry_count, @function
flyology_platform_retry_count:
    lea core_records(%rip), %rcx
    xor %eax, %eax
    mov $MAX_CORES, %edx
1:
    addq CORE_PREEMPTION_RETRY_COUNT(%rcx), %rax
    jc fatal
    add $(1 << CORE_RECORD_SHIFT), %rcx
    dec %edx
    jnz 1b
    ret

#ifndef FLYOLOGY_EXCEPTIONS
.global __gnat_personality_v0
.type __gnat_personality_v0, @function
__gnat_personality_v0:
    jmp fatal

.global _Unwind_Resume
.type _Unwind_Resume, @function
_Unwind_Resume:
    jmp fatal
#endif
#endif

.global flyology_interrupts_report_pass
.type flyology_interrupts_report_pass, @function
flyology_interrupts_report_pass:
    push %rbx
    mov %edi, %ebx
    cmpq $1, %gs:104
    jne fatal
    call serial_lock_acquire
    lea interrupt_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea interrupt_idt_transition_suffix(%rip), %rdi
    call serial_puts
    lea interrupt_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea interrupt_core_suffix(%rip), %rdi
    call serial_puts
    lea interrupt_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea interrupt_frame_suffix(%rip), %rdi
    call serial_puts
    lea interrupt_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea interrupt_epoch_suffix(%rip), %rdi
    call serial_puts
    lea interrupt_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea interrupt_parallel_suffix(%rip), %rdi
    call serial_puts
    lea interrupt_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea interrupt_deferred_suffix(%rip), %rdi
    call serial_puts
    call serial_lock_release
    pop %rbx
    ret

.global flyology_conformance_report_failure
.type flyology_conformance_report_failure, @function
flyology_conformance_report_failure:
    jmp fatal

.global flyology_rts_lock_acquire
.type flyology_rts_lock_acquire, @function
flyology_rts_lock_acquire:
    cmpq $255, %gs:88
    jae fatal
    cmpq $0, %gs:88
    jne 3f
    incq %gs:88
    mov $1, %eax
1:
    xchg %eax, rts_lock(%rip)
    test %eax, %eax
    jz 2f
    pause
    mov $1, %eax
    jmp 1b
2:
    ret
3:
    incq %gs:88
    ret

.global flyology_rts_lock_try_acquire
.type flyology_rts_lock_try_acquire, @function
flyology_rts_lock_try_acquire:
    cmpq $0, %gs:88
    jne 2f
    cmpl $0, serial_lock(%rip)
    jne 2f
    mov $1, %eax
    xchg %eax, rts_lock(%rip)
    test %eax, %eax
    jne 2f
    movq $1, %gs:88
    mov $1, %eax
    ret
2:
    xor %eax, %eax
    ret

.global flyology_rts_lock_release
.type flyology_rts_lock_release, @function
flyology_rts_lock_release:
    cmpq $0, %gs:88
    je fatal
    cmpq $1, %gs:88
    je 2f
    decq %gs:88
    ret
2:
    movl $0, rts_lock(%rip)
    decq %gs:88
    mov %gs:48, %rax
    cmp %gs:56, %rax
    je 1f
    movq $1, %gs:96
#ifdef FLYOLOGY_PREEMPTION
    cmpq $0, %gs:112
    jne 1f
    pushfq
    pop %rcx
    test $0x200, %rcx
    jz 1f
    int $RESCHEDULE_VECTOR
#endif
1:
    ret
#endif

.type print_online, @function
print_online:
    push %rbx
    mov %edi, %ebx
    lea online_prefix(%rip), %rdi
    call serial_lock_acquire
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    mov $'\n', %dil
    call serial_putc
    call serial_lock_release
    pop %rbx
    ret

.type serial_init, @function
serial_init:
    mov $COM1 + 1, %dx
    xor %al, %al
    out %al, %dx
    mov $COM1 + 3, %dx
    mov $0x80, %al
    out %al, %dx
    mov $COM1, %dx
    mov $1, %al
    out %al, %dx
    mov $COM1 + 1, %dx
    xor %al, %al
    out %al, %dx
    mov $COM1 + 3, %dx
    mov $3, %al
    out %al, %dx
    mov $COM1 + 2, %dx
    mov $0xc7, %al
    out %al, %dx
    mov $COM1 + 4, %dx
    mov $0x0b, %al
    out %al, %dx
    ret

.type serial_putc, @function
serial_putc:
    mov %dil, %cl
1:
    mov $COM1 + 5, %dx
    in %dx, %al
    test $0x20, %al
    jz 1b
    mov $COM1, %dx
    mov %cl, %al
    out %al, %dx
    ret

.type serial_puts, @function
serial_puts:
    push %rbx
    mov %rdi, %rbx
1:
    movzbl (%rbx), %edi
    test %dil, %dil
    jz 2f
    call serial_putc
    inc %rbx
    jmp 1b
2:
    pop %rbx
    ret

.type serial_puts_locked, @function
serial_puts_locked:
    push %rdi
    call serial_lock_acquire
    pop %rdi
    call serial_puts
    call serial_lock_release
    ret

.type serial_lock_acquire, @function
serial_lock_acquire:
    mov $1, %eax
1:
    xchg %eax, serial_lock(%rip)
    test %eax, %eax
    jz 2f
    pause
    mov $1, %eax
    jmp 1b
2:
    ret

.type serial_lock_release, @function
serial_lock_release:
    movl $0, serial_lock(%rip)
    ret

fatal:
    lea fail_marker(%rip), %rdi
    call serial_puts_locked
    jmp halt

.section .rodata
.section .rodata.flyology_interrupt_layout, "a", @progbits
.short 256, 0, 120, 128, 136, 144, 152, 160
.short 168, 176, 184, 192, 200, 208, 216

.section .rodata
.balign 16
interrupt_simd_canary:
.quad 0x0123456789abcdef, 0xfedcba9876543210
.quad 0x55aa55aa33cc33cc, 0xaa55aa55cc33cc33
.balign 8
preemption_gpr_canaries:
.quad 0x1111111111111111, 0x2222222222222222
.quad 0x3333333333333333, 0x4444444444444444
.quad 0x5555555555555555, 0x6666666666666666
.quad 0x8888888888888888, 0x9999999999999999
.quad 0xaaaaaaaaaaaaaaaa, 0xbbbbbbbbbbbbbbbb
.quad 0xcccccccccccccccc, 0xdddddddddddddddd
.quad 0xeeeeeeeeeeeeeeee, 0xf0f0f0f0f0f0f0f0
online_prefix: .asciz "FLYOLOGY:CORE:ONLINE:"
ada_pass:      .asciz "FLYOLOGY:ADA:MAIN:PASS\n"
ada_elaboration_pass: .asciz "FLYOLOGY:ADA:ELABORATION:PASS\n"
boot_pass:       .asciz "FLYOLOGY:BOOT:PASS\n"
exception_pass:.asciz "FLYOLOGY:RTS:EXCEPTION:PASS\n"
exception_detail:.asciz "FLYOLOGY:RTS:EXCEPTION:DETAIL:"
#ifdef FLYOLOGY_INTERRUPTS
interrupt_core_prefix: .asciz "FLYOLOGY:INTERRUPTS:CORE:"
interrupt_idt_transition_suffix: .asciz ":IDT_TRANSITION:PASS\n"
interrupt_core_suffix: .asciz ":SUBSTRATE:PASS\n"
interrupt_frame_suffix: .asciz ":INTERRUPT_FRAME:PASS\n"
interrupt_epoch_suffix: .asciz ":REQUEST_EPOCH:PASS\n"
interrupt_parallel_suffix: .asciz ":PARALLEL:PASS\n"
interrupt_deferred_suffix: .asciz ":DEFERRED_REQUEST:PASS\n"
interrupt_ipi_suffix: .asciz ":RESCHEDULE_IPI:PASS\n"
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
preemption_canary_status_failure: .asciz "FLYOLOGY:FAIL:X86_CANARY_STATUS\n"
preemption_canary_gpr_failure: .asciz "FLYOLOGY:FAIL:X86_CANARY_GPR\n"
preemption_canary_simd_failure: .asciz "FLYOLOGY:FAIL:X86_CANARY_SIMD\n"
preemption_canary_fp_failure: .asciz "FLYOLOGY:FAIL:X86_CANARY_FP\n"
#endif
fail_marker:   .asciz "FLYOLOGY:FAIL:X86_BOOT\n"
last_chance_marker: .asciz "FLYOLOGY:LAST_CHANCE:X86_64\n"
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
.balign 8
rts_apic_rates: .skip MAX_CORES * 8
#endif
#endif
memory_usable_found: .skip 1
.balign 8
bsp_record: .skip 8
.balign 64
core_records: .skip MAX_CORES * (1 << CORE_RECORD_SHIFT)
#ifdef FLYOLOGY_INTERRUPTS
.balign 64
interrupt_frames: .skip MAX_CORES * 256
.balign 4096
xsave_areas: .skip MAX_CORES * 4096
.balign 128
tss_records: .skip MAX_CORES * 128
.balign 4096
gdt_tables: .skip MAX_CORES * (1 << GDT_SHIFT)
.balign 16
exception_stacks: .skip MAX_CORES * (1 << EXCEPTION_STACK_SHIFT)
#endif
.balign 16
idt_descriptor: .skip 10
#ifdef FLYOLOGY_INTERRUPTS
.balign 16
interrupt_idt_descriptor: .skip 10
#endif
.balign 4096
idt_table: .skip 256 * 16
#ifdef FLYOLOGY_INTERRUPTS
.balign 4096
interrupt_idt_table: .skip 256 * 16
#endif
.balign 16
emergency_stack: .skip 4096
emergency_stack_end:
.balign 16
core_stacks: .skip MAX_CORES * (1 << STACK_SHIFT)

.section .note.GNU-stack, "", @progbits
