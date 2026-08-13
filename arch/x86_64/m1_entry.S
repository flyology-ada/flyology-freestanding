/* SPDX-License-Identifier: MIT OR Apache-2.0 */

.set MAX_CORES, 4
.set STACK_SHIFT, 16
.set CORE_RECORD_SHIFT, 6
.set COM1, 0x3f8

.section .text.entry, "ax", @progbits
.global _start
.type _start, @function
_start:
    cli
    cld
    lea core_stacks + (1 << STACK_SHIFT)(%rip), %rsp
    xor %ebp, %ebp
    call serial_init
#ifdef FLYOLOGY_M1_FAULT_LAST_CHANCE
    call flyology_last_chance_probe
#endif
    call initialize_idt

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

    mov bsp_record(%rip), %rdi
    test %rdi, %rdi
    jz fatal
    call set_core_pointer
    mov $0x802, %ecx
    rdmsr
    mov bsp_record(%rip), %rdi
    cmp 16(%rdi), %eax
    jne fatal

    call adainit
    call _ada_flyology_m1
    call adafinal
    lea ada_pass(%rip), %rdi
    call serial_puts_locked

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
    lea m1_pass(%rip), %rdi
    call serial_puts_locked
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

.global __gnat_last_chance_handler
.global __gnat_rcheck_CE_Explicit_Raise
.global __gnat_rcheck_CE_Range_Check
.global __gnat_rcheck_PE_Explicit_Raise
.global __gnat_rcheck_SE_Explicit_Raise
.type __gnat_last_chance_handler, @function
__gnat_last_chance_handler:
__gnat_rcheck_CE_Explicit_Raise:
__gnat_rcheck_CE_Range_Check:
__gnat_rcheck_PE_Explicit_Raise:
__gnat_rcheck_SE_Explicit_Raise:
    cli
    movl $0, serial_lock(%rip)
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
online_prefix: .asciz "FLYOLOGY:CORE:ONLINE:"
ada_pass:      .asciz "FLYOLOGY:ADA:MAIN:PASS\n"
m1_pass:       .asciz "FLYOLOGY:M1:PASS\n"
fail_marker:   .asciz "FLYOLOGY:FAIL:X86_BOOT\n"
last_chance_marker: .asciz "FLYOLOGY:LAST_CHANCE:X86_64\n"
digits:        .ascii "0123"

.section .bss
.balign 4
serial_lock: .skip 4
online_count: .skip 4
memory_usable_found: .skip 1
.balign 8
bsp_record: .skip 8
.balign 64
core_records: .skip MAX_CORES * (1 << CORE_RECORD_SHIFT)
.balign 16
idt_descriptor: .skip 10
.balign 4096
idt_table: .skip 256 * 16
.balign 16
emergency_stack: .skip 4096
emergency_stack_end:
.balign 16
core_stacks: .skip MAX_CORES * (1 << STACK_SHIFT)

.section .note.GNU-stack, "", @progbits
