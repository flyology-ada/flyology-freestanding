/* SPDX-License-Identifier: MIT OR Apache-2.0 */

/* The compiler allocator is a deliberately bounded ABI facade.  Deterministic
   alignment/capacity arithmetic is mirrored by Flyology.Allocator_Model; this
   file owns only the atomic reservation and C symbols required by GNAT. */

typedef __UINT8_TYPE__ u8;
typedef __SIZE_TYPE__ usize;

enum {
    ALLOCATION_ALIGNMENT = 16,
    ALLOCATION_CAPACITY = 65536
};

static u8 allocation_pool[ALLOCATION_CAPACITY] __attribute__((aligned(16)));
static usize allocation_used;

#ifdef FLYOLOGY_ALLOCATOR_TEST
static usize test_gate_target;
static usize test_gate_arrived;
static u8 test_gate_released;
static usize test_cas_retries;

static void test_wait_for_contenders(void)
{
    usize target = __atomic_load_n(&test_gate_target, __ATOMIC_ACQUIRE);
    usize arrived;
    if (target == 0)
        return;
    arrived = __atomic_add_fetch(&test_gate_arrived, 1, __ATOMIC_ACQ_REL);
    if (arrived == target)
        __atomic_store_n(&test_gate_released, 1, __ATOMIC_RELEASE);
    else
        while (__atomic_load_n(&test_gate_released, __ATOMIC_ACQUIRE) == 0) {
        }
}
#endif

static void *allocator_reserve(usize count)
{
    usize aligned;
    usize start;
    usize next;

    if (count == 0)
        aligned = ALLOCATION_ALIGNMENT;
    else {
        if (count > ALLOCATION_CAPACITY)
            return 0;
        aligned = ((count - 1U) / ALLOCATION_ALIGNMENT + 1U) *
            ALLOCATION_ALIGNMENT;
    }

    start = __atomic_load_n(&allocation_used, __ATOMIC_ACQUIRE);
#ifdef FLYOLOGY_ALLOCATOR_TEST
    test_wait_for_contenders();
#endif
    for (;;) {
        if (start > ALLOCATION_CAPACITY ||
            start % ALLOCATION_ALIGNMENT != 0 ||
            aligned > ALLOCATION_CAPACITY - start)
            return 0;
        next = start + aligned;
        if (__atomic_compare_exchange_n(&allocation_used, &start, next, 1,
                                        __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))
            return allocation_pool + start;
#ifdef FLYOLOGY_ALLOCATOR_TEST
        __atomic_fetch_add(&test_cas_retries, 1, __ATOMIC_RELAXED);
#endif
    }
}

#ifdef FLYOLOGY_ALLOCATOR_TEST
void *flyology_allocator_test_reserve(usize count)
{
    return allocator_reserve(count);
}

void flyology_allocator_test_reset(void)
{
    __atomic_store_n(&allocation_used, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&test_gate_target, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&test_gate_arrived, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&test_gate_released, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&test_cas_retries, 0, __ATOMIC_RELEASE);
}

usize flyology_allocator_test_used(void)
{
    return __atomic_load_n(&allocation_used, __ATOMIC_ACQUIRE);
}

void flyology_allocator_test_set_used(usize used)
{
    __atomic_store_n(&allocation_used, used, __ATOMIC_RELEASE);
}

void flyology_allocator_test_gate(usize contenders)
{
    __atomic_store_n(&test_gate_arrived, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&test_gate_released, 0, __ATOMIC_RELEASE);
    __atomic_store_n(&test_gate_target, contenders, __ATOMIC_RELEASE);
}

usize flyology_allocator_test_retries(void)
{
    return __atomic_load_n(&test_cas_retries, __ATOMIC_ACQUIRE);
}
#else
extern void __gnat_rcheck_SE_Explicit_Raise(void *, int)
    __attribute__((noreturn));

void *malloc(usize count)
{
    return allocator_reserve(count);
}

void *__gnat_malloc(usize count)
{
    void *result = allocator_reserve(count);
    if (result == 0)
        __gnat_rcheck_SE_Explicit_Raise((void *)"dynamic allocation", 0);
    return result;
}

void free(void *object)
{
    (void)object;
}
#endif
