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
#if defined(FLYOLOGY_M3) || defined(FLYOLOGY_EXCEPTION)
    /* Base revision 6 disables FP/SIMD.  No compiler-generated Ada call may
       precede normalization, including the injected last-chance probe. */
#ifdef FLYOLOGY_EXCEPTION
    call initialize_exception_fp
#else
    call initialize_task_fp
#endif
#endif
#ifdef FLYOLOGY_M1_FAULT_LAST_CHANCE
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
#ifdef FLYOLOGY_M2
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

#ifdef FLYOLOGY_EXCEPTION
    call flyology_exception_initialize
#endif
    call adainit
#ifdef FLYOLOGY_EXCEPTION
#ifndef FLYOLOGY_M3
    call _ada_exception_probe
    lea exception_pass(%rip), %rdi
    call serial_puts_locked
#endif
#endif
#ifdef FLYOLOGY_M3
    lea ada_elaboration_pass(%rip), %rdi
    call serial_puts_locked
#endif
#ifdef FLYOLOGY_M2
#ifndef FLYOLOGY_M3
    call _ada_flyology_m2
#endif
#else
#if defined(FLYOLOGY_EXCEPTION) && !defined(FLYOLOGY_M3)
    call adafinal
#else
    call _ada_flyology_m1
    call adafinal
#endif
#endif
#ifndef FLYOLOGY_M3
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
#ifdef FLYOLOGY_M2
    call initialize_task_fp
    call initialize_x2apic
    call initialize_cpu_tables
#ifdef FLYOLOGY_M3
    xor %edi, %edi
    call flyology_m3_prepare_environment
#else
    sti
    call flyology_m2_core_entry
    cli
    call m2_idle_reschedule_test
    lock incl m2_complete_count(%rip)
#endif
wait_m2_complete:
#ifdef FLYOLOGY_M3
    pause
    mov dispatcher_ready_count(%rip), %eax
    cmp %r13d, %eax
    jne wait_m2_complete
    sti
    call _ada_flyology_m3
    lea ada_pass(%rip), %rdi
    call serial_puts_locked
    lea m3_boot_pass(%rip), %rdi
    call serial_puts_locked
    call adafinal
    cli
    call flyology_m3_environment_complete
    jmp fatal
#else
    pause
    mov m2_complete_count(%rip), %eax
    cmp %r13d, %eax
    jne wait_m2_complete
    lea m2_pass(%rip), %rdi
    call serial_puts_locked
    call adafinal
#endif
#else
    lea m1_pass(%rip), %rdi
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
#ifdef FLYOLOGY_M2
    call initialize_task_fp
    call initialize_x2apic
    call initialize_cpu_tables
#ifdef FLYOLOGY_M3
    mov %gs:0, %rdi
    call flyology_m3_prepare_ap
    jmp fatal
#else
    sti
    call flyology_m2_core_entry
    cli
    call m2_idle_reschedule_test
    lock incl m2_complete_count(%rip)
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
#ifdef FLYOLOGY_M2
    lea idt_table(%rip), %rsi
    lea m2_idt_table(%rip), %rdi
    mov $512, %ecx
    rep movsq
    movw $(256 * 16 - 1), m2_idt_descriptor(%rip)
    lea m2_idt_table(%rip), %rax
    mov %rax, m2_idt_descriptor + 2(%rip)
    lea m2_idt_table + TIMER_VECTOR * 16(%rip), %rdi
#else
    lea idt_table + TIMER_VECTOR * 16(%rip), %rdi
#endif
#ifdef FLYOLOGY_M2
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
    lea m2_idt_table + RESCHEDULE_VECTOR * 16(%rip), %rdi
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
    lea m2_idt_table(%rip), %rdi
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
    /* The minimal M1 IDT reports but does not resume an exception. */
    lea emergency_stack_end(%rip), %rsp
    movl $0, serial_lock(%rip)
    lea fail_marker(%rip), %rdi
    call serial_puts
    jmp halt

#ifdef FLYOLOGY_M2
.type idt_transition_vector, @function
idt_transition_vector:
    movq $1, %gs:104
    iretq

.type reschedule_vector, @function
reschedule_vector:
    pushq $RESCHEDULE_VECTOR
    jmp m2_interrupt_common

.type timer_vector, @function
timer_vector:
    pushq $TIMER_VECTOR

.type m2_interrupt_common, @function
m2_interrupt_common:
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
    cmpq $0, %gs:80
    je 3f
    cmpw $0x027f, 0(%rdi)
    jne fatal
    cmpl $0x1f80, 24(%rdi)
    jne fatal
    mov m2_simd_canary(%rip), %rax
    cmp %rax, 160(%rdi)
    jne fatal
    mov m2_simd_canary + 8(%rip), %rax
    cmp %rax, 168(%rdi)
    jne fatal
    mov m2_simd_canary + 16(%rip), %rax
    cmp %rax, 400(%rdi)
    jne fatal
    mov m2_simd_canary + 24(%rip), %rax
    cmp %rax, 408(%rdi)
    jne fatal
3:

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
    mov $0x80b, %ecx
    xor %eax, %eax
    xor %edx, %edx
    wrmsr
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
.global __gnat_rcheck_PE_Explicit_Raise
.global __gnat_rcheck_SE_Explicit_Raise
.type __gnat_last_chance_handler, @function
__gnat_last_chance_handler:
#ifndef FLYOLOGY_EXCEPTION
__gnat_rcheck_CE_Explicit_Raise:
__gnat_rcheck_CE_Access_Check:
__gnat_rcheck_CE_Index_Check:
__gnat_rcheck_CE_Invalid_Data:
__gnat_rcheck_CE_Overflow_Check:
__gnat_rcheck_CE_Range_Check:
__gnat_rcheck_PE_Explicit_Raise:
__gnat_rcheck_SE_Explicit_Raise:
#endif
    cli
    movl $0, serial_lock(%rip)
#ifdef FLYOLOGY_EXCEPTION
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

#ifdef FLYOLOGY_EXCEPTION
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

#ifdef FLYOLOGY_M2
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
    lidt m2_idt_descriptor(%rip)
    pop %r12
    pop %rbx
    ret

.type m2_arm_task_timer, @function
m2_arm_task_timer:
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

.global flyology_m2_wait_for_timer_request
.type flyology_m2_wait_for_timer_request, @function
flyology_m2_wait_for_timer_request:
    sub $24, %rsp
    movw $0x027f, 0(%rsp)
    fldcw 0(%rsp)
    movq $1, %gs:80
    movdqa m2_simd_canary(%rip), %xmm0
    movdqa m2_simd_canary + 16(%rip), %xmm15
    call m2_arm_task_timer
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
    pcmpeqb m2_simd_canary(%rip), %xmm0
    pmovmskb %xmm0, %eax
    cmp $0xffff, %eax
    jne fatal
    pcmpeqb m2_simd_canary + 16(%rip), %xmm15
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

.global flyology_m2_acknowledge_requests
.type flyology_m2_acknowledge_requests, @function
flyology_m2_acknowledge_requests:
    mov %gs:48, %rdx
    mov %rdx, %gs:56
    mov %gs:64, %rax
    ret

.global flyology_m2_parallel_task_barrier
.type flyology_m2_parallel_task_barrier, @function
flyology_m2_parallel_task_barrier:
    lock incl m2_task_barrier_count(%rip)
1:
    mov m2_task_barrier_count(%rip), %eax
    cmp cpu_count(%rip), %eax
    je 2f
    pause
    jmp 1b
2:
    ret

.global flyology_m2_arm_deferred_timer
.type flyology_m2_arm_deferred_timer, @function
flyology_m2_arm_deferred_timer:
    andq $-3, %gs:72
    call m2_arm_task_timer
1:
    testq $2, %gs:72
    jnz 2f
    pause
    jmp 1b
2:
    ret

.global flyology_m2_consume_deferred
.type flyology_m2_consume_deferred, @function
flyology_m2_consume_deferred:
    xor %eax, %eax
    xchg %rax, %gs:96
    ret

.global flyology_m2_disable_dispatch
.type flyology_m2_disable_dispatch, @function
flyology_m2_disable_dispatch:
    cli
    ret

.global flyology_m2_enable_dispatch
.type flyology_m2_enable_dispatch, @function
flyology_m2_enable_dispatch:
    sti
    ret

.type m2_idle_reschedule_test, @function
m2_idle_reschedule_test:
    push %rbx
    push %r12
    movq $0, %gs:72
    lock incl m2_idle_ready_count(%rip)
    mov %gs:0, %ebx
    test %ebx, %ebx
    jnz 3f
1:
    pause
    mov m2_idle_ready_count(%rip), %eax
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
    call flyology_m2_acknowledge_requests
    test $1, %eax
    jz fatal
    mov %ebx, %edi
    call m2_report_ipi_pass
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
    call flyology_m2_acknowledge_requests
    test $2, %eax
    jz fatal
    mov %ebx, %edi
    call m2_report_timer_pass
    pop %r12
    pop %rbx
    ret

.type m2_report_ipi_pass, @function
m2_report_ipi_pass:
    push %rbx
    mov %edi, %ebx
    call serial_lock_acquire
    lea m2_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea m2_ipi_suffix(%rip), %rdi
    call serial_puts
    call serial_lock_release
    pop %rbx
    ret

.type m2_report_timer_pass, @function
m2_report_timer_pass:
    push %rbx
    mov %edi, %ebx
    call serial_lock_acquire
    lea m2_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea m2_timer_suffix(%rip), %rdi
    call serial_puts
    call serial_lock_release
    pop %rbx
    ret

.global flyology_current_core
.type flyology_current_core, @function
flyology_current_core:
    mov %gs:0, %rax
    ret

#ifdef FLYOLOGY_M3
.weak adafinal
.type adafinal, @function
adafinal:
    ret

.global flyology_m3_boot_cpu_count
.type flyology_m3_boot_cpu_count, @function
flyology_m3_boot_cpu_count:
    mov cpu_count(%rip), %eax
    ret

.global flyology_m3_dispatcher_ready
.type flyology_m3_dispatcher_ready, @function
flyology_m3_dispatcher_ready:
    lock incl dispatcher_ready_count(%rip)
    ret

.global flyology_m3_prepare_idle
.type flyology_m3_prepare_idle, @function
flyology_m3_prepare_idle:
    movq %gs:48, %rax
    movq %rax, %gs:56
    ret

.global flyology_m3_idle
.type flyology_m3_idle, @function
flyology_m3_idle:
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

.global flyology_m3_kick_core
.type flyology_m3_kick_core, @function
flyology_m3_kick_core:
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

.global flyology_m3_report_ordinary_pass
.type flyology_m3_report_ordinary_pass, @function
flyology_m3_report_ordinary_pass:
    lea m3_ordinary_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m3_report_specific_pass
.type flyology_m3_report_specific_pass, @function
flyology_m3_report_specific_pass:
    lea m3_specific_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m3_report_parallel_pass
.type flyology_m3_report_parallel_pass, @function
flyology_m3_report_parallel_pass:
    lea m3_parallel_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m3_report_auto_master_pass
.type flyology_m3_report_auto_master_pass, @function
flyology_m3_report_auto_master_pass:
    lea m3_auto_master_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_reclamation_pass
.type flyology_m4_report_reclamation_pass, @function
flyology_m4_report_reclamation_pass:
    lea m4_reclamation_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_delay_pass
.type flyology_m4_report_delay_pass, @function
flyology_m4_report_delay_pass:
    lea m4_delay_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_absolute_delay_pass
.type flyology_m4_report_absolute_delay_pass, @function
flyology_m4_report_absolute_delay_pass:
    lea m4_absolute_delay_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_protected_pass
.type flyology_m4_report_protected_pass, @function
flyology_m4_report_protected_pass:
    lea m4_protected_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_protected_entry_pass
.type flyology_m4_report_protected_entry_pass, @function
flyology_m4_report_protected_entry_pass:
    lea m4_protected_entry_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_finalization_pass
.type flyology_m4_report_finalization_pass, @function
flyology_m4_report_finalization_pass:
    lea m4_finalization_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_rendezvous_pass
.type flyology_m4_report_rendezvous_pass, @function
flyology_m4_report_rendezvous_pass:
    lea m4_rendezvous_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_priority_pass
.type flyology_m4_report_priority_pass, @function
flyology_m4_report_priority_pass:
    lea m4_priority_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_conditional_pass
.type flyology_m4_report_conditional_pass, @function
flyology_m4_report_conditional_pass:
    lea m4_conditional_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_timed_entry_pass
.type flyology_m4_report_timed_entry_pass, @function
flyology_m4_report_timed_entry_pass:
    lea m4_timed_entry_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_dynamic_task_pass
.type flyology_m4_report_dynamic_task_pass, @function
flyology_m4_report_dynamic_task_pass:
    lea m4_dynamic_task_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_selective_wait_pass
.type flyology_m4_report_selective_wait_pass, @function
flyology_m4_report_selective_wait_pass:
    lea m4_selective_wait_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_abort_pass
.type flyology_m4_report_abort_pass, @function
flyology_m4_report_abort_pass:
    lea m4_abort_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_abort_rendezvous_pass
.type flyology_m4_report_abort_rendezvous_pass, @function
flyology_m4_report_abort_rendezvous_pass:
    lea m4_abort_rendezvous_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_abort_timeout_pass
.type flyology_m4_report_abort_timeout_pass, @function
flyology_m4_report_abort_timeout_pass:
    lea m4_abort_timeout_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_abort_accepted_pass
.type flyology_m4_report_abort_accepted_pass, @function
flyology_m4_report_abort_accepted_pass:
    lea m4_abort_accepted_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m4_report_abort_protected_pass
.type flyology_m4_report_abort_protected_pass, @function
flyology_m4_report_abort_protected_pass:
    lea m4_abort_protected_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m3_report_master_pass
.type flyology_m3_report_master_pass, @function
flyology_m3_report_master_pass:
    lea m3_master_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m3_report_stack_pass
.type flyology_m3_report_stack_pass, @function
flyology_m3_report_stack_pass:
    lea m3_stack_pass(%rip), %rdi
    jmp serial_puts_locked

.global flyology_m3_parallel_barrier
.type flyology_m3_parallel_barrier, @function
flyology_m3_parallel_barrier:
    test %edi, %edi
    jz fatal
    mov %edi, %eax
    imul cpu_count(%rip), %eax
    lock incl m3_parallel_barrier_count(%rip)
1:
    cmp m3_parallel_barrier_count(%rip), %eax
    je 2f
    pause
    jmp 1b
2:
    ret

.global flyology_m4_read_clock
.type flyology_m4_read_clock, @function
flyology_m4_read_clock:
    lfence
    rdtsc
    shl $32, %rdx
    or %rdx, %rax
    lfence
    ret

.global flyology_m4_clock_frequency
.type flyology_m4_clock_frequency, @function
flyology_m4_clock_frequency:
    mov $1000000000, %eax
    ret

.type m4_calibrate_apic_timer, @function
m4_calibrate_apic_timer:
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
    call flyology_m4_read_clock
    mov %rax, %r8
1:
    mov $0x839, %ecx
    rdmsr
    mov $0xffffffff, %r9d
    sub %eax, %r9d
    cmp $100000, %r9d
    jb 1b
    call flyology_m4_read_clock
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

.global flyology_m4_cancel_timer
.type flyology_m4_cancel_timer, @function
flyology_m4_cancel_timer:
    mov $0x832, %ecx
    mov $(0x10000 | TIMER_VECTOR), %eax
    xor %edx, %edx
    wrmsr
    mov $0x838, %ecx
    xor %eax, %eax
    xor %edx, %edx
    wrmsr
    ret

.global flyology_m4_program_timer
.type flyology_m4_program_timer, @function
flyology_m4_program_timer:
    push %rbx
    push %r12
    push %r13
    mov %rdi, %r12
    call flyology_m4_read_clock
    cmp %rax, %r12
    jbe 1f
    sub %rax, %r12
    jmp 2f
1:
    mov $1, %r12
2:
    mov %gs:0, %rbx
    lea m4_apic_rates(%rip), %r13
    mov (%r13,%rbx,8), %r11
    test %r11, %r11
    jnz 3f
    call m4_calibrate_apic_timer
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

#ifndef FLYOLOGY_EXCEPTION
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

.global flyology_m2_report_pass
.type flyology_m2_report_pass, @function
flyology_m2_report_pass:
    push %rbx
    mov %edi, %ebx
    cmpq $1, %gs:104
    jne fatal
    call serial_lock_acquire
    lea m2_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea m2_idt_transition_suffix(%rip), %rdi
    call serial_puts
    lea m2_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea m2_core_suffix(%rip), %rdi
    call serial_puts
    lea m2_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea m2_frame_suffix(%rip), %rdi
    call serial_puts
    lea m2_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea m2_epoch_suffix(%rip), %rdi
    call serial_puts
    lea m2_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea m2_parallel_suffix(%rip), %rdi
    call serial_puts
    lea m2_core_prefix(%rip), %rdi
    call serial_puts
    lea digits(%rip), %rax
    mov (%rax,%rbx,1), %dil
    call serial_putc
    lea m2_deferred_suffix(%rip), %rdi
    call serial_puts
    call serial_lock_release
    pop %rbx
    ret

.global flyology_m2_report_failure
.type flyology_m2_report_failure, @function
flyology_m2_report_failure:
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
m2_simd_canary:
.quad 0x0123456789abcdef, 0xfedcba9876543210
.quad 0x55aa55aa33cc33cc, 0xaa55aa55cc33cc33
online_prefix: .asciz "FLYOLOGY:CORE:ONLINE:"
ada_pass:      .asciz "FLYOLOGY:ADA:MAIN:PASS\n"
ada_elaboration_pass: .asciz "FLYOLOGY:ADA:ELABORATION:PASS\n"
m1_pass:       .asciz "FLYOLOGY:M1:PASS\n"
exception_pass:.asciz "FLYOLOGY:M4:EXCEPTION:PASS\n"
exception_detail:.asciz "FLYOLOGY:M4:EXCEPTION:DETAIL:"
#ifdef FLYOLOGY_M2
m2_core_prefix: .asciz "FLYOLOGY:M2:CORE:"
m2_idt_transition_suffix: .asciz ":IDT_TRANSITION:PASS\n"
m2_core_suffix: .asciz ":SUBSTRATE:PASS\n"
m2_frame_suffix: .asciz ":INTERRUPT_FRAME:PASS\n"
m2_epoch_suffix: .asciz ":REQUEST_EPOCH:PASS\n"
m2_parallel_suffix: .asciz ":PARALLEL:PASS\n"
m2_deferred_suffix: .asciz ":DEFERRED_REQUEST:PASS\n"
m2_ipi_suffix: .asciz ":RESCHEDULE_IPI:PASS\n"
m2_timer_suffix: .asciz ":TIMER:PASS\n"
m2_pass:       .asciz "FLYOLOGY:M2:PASS\n"
m3_boot_pass:  .asciz "FLYOLOGY:M3:BOOT_SUBSTRATE:PASS\n"
m3_ordinary_pass: .asciz "FLYOLOGY:M3:ORDINARY_TASKS:PASS\n"
m3_specific_pass: .asciz "FLYOLOGY:M3:SPECIFIC_CPU:PASS\n"
m3_parallel_pass: .asciz "FLYOLOGY:M3:AUTO_PARALLEL:PASS\n"
m3_auto_master_pass: .asciz "FLYOLOGY:M3:AUTO_MASTER:PASS\n"
m4_reclamation_pass: .asciz "FLYOLOGY:M4:RECLAMATION:PASS\n"
m3_master_pass: .asciz "FLYOLOGY:M3:NESTED_MASTER:PASS\n"
m3_stack_pass: .asciz "FLYOLOGY:M3:TASK_STACKS:PASS\n"
m4_delay_pass: .asciz "FLYOLOGY:M4:DELAYS:PASS\n"
m4_absolute_delay_pass: .asciz "FLYOLOGY:M4:ABSOLUTE_DELAY:PASS\n"
m4_protected_pass: .asciz "FLYOLOGY:M4:PROTECTED:PASS\n"
m4_protected_entry_pass: .asciz "FLYOLOGY:M4:PROTECTED_ENTRY:PASS\n"
m4_finalization_pass: .asciz "FLYOLOGY:M4:FINALIZATION:PASS\n"
m4_rendezvous_pass: .asciz "FLYOLOGY:M4:RENDEZVOUS:PASS\n"
m4_priority_pass: .asciz "FLYOLOGY:M4:DYNAMIC_PRIORITY:PASS\n"
m4_conditional_pass: .asciz "FLYOLOGY:M4:CONDITIONAL_ENTRY:PASS\n"
m4_timed_entry_pass: .asciz "FLYOLOGY:M4:TIMED_ENTRY:PASS\n"
m4_dynamic_task_pass: .asciz "FLYOLOGY:M4:DYNAMIC_TASK:PASS\n"
m4_selective_wait_pass: .asciz "FLYOLOGY:M4:SELECTIVE_WAIT:PASS\n"
m4_abort_pass: .asciz "FLYOLOGY:M4:ABORT:PASS\n"
m4_abort_rendezvous_pass: .asciz "FLYOLOGY:M4:ABORT_RENDEZVOUS:PASS\n"
m4_abort_timeout_pass: .asciz "FLYOLOGY:M4:ABORT_TIMEOUT:PASS\n"
m4_abort_accepted_pass: .asciz "FLYOLOGY:M4:ABORT_ACCEPTED:PASS\n"
m4_abort_protected_pass: .asciz "FLYOLOGY:M4:ABORT_PROTECTED:PASS\n"
#endif
fail_marker:   .asciz "FLYOLOGY:FAIL:X86_BOOT\n"
last_chance_marker: .asciz "FLYOLOGY:LAST_CHANCE:X86_64\n"
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
.balign 8
m4_apic_rates: .skip MAX_CORES * 8
#endif
#endif
memory_usable_found: .skip 1
.balign 8
bsp_record: .skip 8
.balign 64
core_records: .skip MAX_CORES * (1 << CORE_RECORD_SHIFT)
#ifdef FLYOLOGY_M2
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
#ifdef FLYOLOGY_M2
.balign 16
m2_idt_descriptor: .skip 10
#endif
.balign 4096
idt_table: .skip 256 * 16
#ifdef FLYOLOGY_M2
.balign 4096
m2_idt_table: .skip 256 * 16
#endif
.balign 16
emergency_stack: .skip 4096
emergency_stack_end:
.balign 16
core_stacks: .skip MAX_CORES * (1 << STACK_SHIFT)

.section .note.GNU-stack, "", @progbits
