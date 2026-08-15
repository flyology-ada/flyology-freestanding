/* SPDX-License-Identifier: MIT OR Apache-2.0 */

/* The exception-boundary image executes its Ada probe only on the BSP before
   parking every other core.  It reuses the production allocator arithmetic,
   while this test-only adapter makes that deliberately single-caller contract
   explicit.  Product images supply these symbols from the SMP runtime lock. */

void flyology_rts_lock_acquire(void)
{
}

void flyology_rts_lock_release(void)
{
}
