/* SPDX-License-Identifier: 0BSD */
/* Protocol constants from Limine v12.5.2's 0BSD limine.h. */

.section .limine_requests_start, "aw"
.balign 8
.global limine_requests_start_marker
limine_requests_start_marker:
    .quad 0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf
    .quad 0x785c6ed015d3e316, 0x181e920a7852b9d9

.section .limine_requests, "aw"
.balign 8
.global limine_base_revision
limine_base_revision:
    .quad 0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 6

.global limine_stack_size_request
limine_stack_size_request:
    .quad 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b
    .quad 0x224ef0460a8e8926, 0xe1cb0fc25f46ea3d
    .quad 0, 0, 65536

.global limine_hhdm_request
limine_hhdm_request:
    .quad 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b
    .quad 0x48dcf1cb8ad2b852, 0x63984e959a98244b
    .quad 0, 0

.global limine_paging_mode_request
limine_paging_mode_request:
    .quad 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b
    .quad 0x95c1a0edab0944cb, 0xa4e5cb3842f7488a
    .quad 1, 0, 0, 0, 0

.global limine_memmap_request
limine_memmap_request:
    .quad 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b
    .quad 0x67cf3d9d378a806f, 0xe304acdfc50c3c62
    .quad 0, 0

.global limine_executable_address_request
limine_executable_address_request:
    .quad 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b
    .quad 0x71ba76863cc55f63, 0xb2644a48c516a487
    .quad 0, 0

.global limine_mp_request
limine_mp_request:
    .quad 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b
    .quad 0x95a67b819a1b857e, 0xa0b61b723b6a73e0
    .quad 0, 0, 1

.section .limine_requests_end, "aw"
.balign 8
.global limine_requests_end_marker
limine_requests_end_marker:
    .quad 0xadc0e0531bb10d03, 0x9572709f31764c62

.section .note.GNU-stack, "", @progbits
