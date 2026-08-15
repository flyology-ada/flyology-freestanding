/* SPDX-License-Identifier: MIT OR Apache-2.0 */

/* The compiler allocator is a deliberately bounded ABI facade.  Deterministic
   alignment/capacity and first-fit arithmetic is mirrored by
   Flyology.Allocator_Model.  The existing recursive RTS critical section is
   the sole concurrent mutation authority; this file owns only pool metadata
   and the C symbols required by GNAT. */

typedef __UINT8_TYPE__ u8;
typedef __UINT16_TYPE__ u16;
typedef __SIZE_TYPE__ usize;

enum {
    ALLOCATION_ALIGNMENT = 16,
    ALLOCATION_CAPACITY = 65536,
    ALLOCATION_UNITS = ALLOCATION_CAPACITY / ALLOCATION_ALIGNMENT
};

enum allocator_status {
    ALLOCATOR_OK,
    ALLOCATOR_EXHAUSTED,
    ALLOCATOR_INVALID
};

static u8 allocation_pool[ALLOCATION_CAPACITY] __attribute__((aligned(16)));
static u8 allocation_used[ALLOCATION_UNITS];
static u16 allocation_lengths[ALLOCATION_UNITS];
static usize allocation_live;
static usize allocation_bytes;

extern void flyology_rts_lock_acquire(void);
extern void flyology_rts_lock_release(void);

static usize allocator_rounded_size(usize count)
{
    if (count == 0)
        return ALLOCATION_ALIGNMENT;
    if (count > ALLOCATION_CAPACITY)
        return 0;
    return ((count - 1U) / ALLOCATION_ALIGNMENT + 1U) *
        ALLOCATION_ALIGNMENT;
}

static enum allocator_status allocator_reserve(usize count, void **result)
{
    usize aligned = allocator_rounded_size(count);
    usize needed;
    usize run = 0;
    usize unit;
    usize start = 0;

    *result = 0;
    if (aligned == 0)
        return ALLOCATOR_EXHAUSTED;
    needed = aligned / ALLOCATION_ALIGNMENT;

    flyology_rts_lock_acquire();
    for (unit = 0; unit < ALLOCATION_UNITS; ++unit) {
        if (allocation_used[unit] == 0) {
            if (allocation_lengths[unit] != 0) {
                flyology_rts_lock_release();
                return ALLOCATOR_INVALID;
            }
            ++run;
            if (run == needed) {
                start = unit + 1U - needed;
                break;
            }
        } else {
            run = 0;
        }
    }
    if (run != needed) {
        flyology_rts_lock_release();
        return ALLOCATOR_EXHAUSTED;
    }
    if (allocation_live >= ALLOCATION_UNITS ||
        allocation_bytes > ALLOCATION_CAPACITY - aligned) {
        flyology_rts_lock_release();
        return ALLOCATOR_INVALID;
    }
    for (unit = start; unit < start + needed; ++unit) {
        if (allocation_used[unit] != 0 || allocation_lengths[unit] != 0) {
            flyology_rts_lock_release();
            return ALLOCATOR_INVALID;
        }
    }
    for (unit = start; unit < start + needed; ++unit)
        allocation_used[unit] = 1;
    allocation_lengths[start] = (u16)needed;
    ++allocation_live;
    allocation_bytes += aligned;
    *result = allocation_pool + start * ALLOCATION_ALIGNMENT;
    flyology_rts_lock_release();
    return ALLOCATOR_OK;
}

static enum allocator_status allocator_release(void *object)
{
    usize address;
    usize base;
    usize offset;
    usize start;
    usize length;
    usize unit;

    if (object == 0)
        return ALLOCATOR_OK;
    address = (usize)object;
    base = (usize)allocation_pool;
    if (address < base)
        return ALLOCATOR_INVALID;
    offset = address - base;
    if (offset >= ALLOCATION_CAPACITY ||
        offset % ALLOCATION_ALIGNMENT != 0)
        return ALLOCATOR_INVALID;
    start = offset / ALLOCATION_ALIGNMENT;

    flyology_rts_lock_acquire();
    length = allocation_lengths[start];
    if (length == 0 || length > ALLOCATION_UNITS - start ||
        allocation_live == 0 ||
        allocation_bytes < length * ALLOCATION_ALIGNMENT) {
        flyology_rts_lock_release();
        return ALLOCATOR_INVALID;
    }
    for (unit = start; unit < start + length; ++unit) {
        if (allocation_used[unit] != 1 ||
            (unit != start && allocation_lengths[unit] != 0)) {
            flyology_rts_lock_release();
            return ALLOCATOR_INVALID;
        }
    }
    allocation_lengths[start] = 0;
    for (unit = start; unit < start + length; ++unit)
        allocation_used[unit] = 0;
    --allocation_live;
    allocation_bytes -= length * ALLOCATION_ALIGNMENT;
    flyology_rts_lock_release();
    return ALLOCATOR_OK;
}

#ifdef FLYOLOGY_ALLOCATOR_TEST
void *flyology_allocator_test_reserve(usize count)
{
    void *result;
    return allocator_reserve(count, &result) == ALLOCATOR_OK ? result : 0;
}

int flyology_allocator_test_release(void *object)
{
    return allocator_release(object) == ALLOCATOR_OK;
}

void flyology_allocator_test_reset(void)
{
    usize unit;
    flyology_rts_lock_acquire();
    for (unit = 0; unit < ALLOCATION_UNITS; ++unit) {
        allocation_used[unit] = 0;
        allocation_lengths[unit] = 0;
    }
    allocation_live = 0;
    allocation_bytes = 0;
    flyology_rts_lock_release();
}

usize flyology_allocator_test_live(void)
{
    usize result;
    flyology_rts_lock_acquire();
    result = allocation_live;
    flyology_rts_lock_release();
    return result;
}

usize flyology_allocator_test_bytes(void)
{
    usize result;
    flyology_rts_lock_acquire();
    result = allocation_bytes;
    flyology_rts_lock_release();
    return result;
}
#else
extern void __gnat_rcheck_PE_Explicit_Raise(void *, int)
    __attribute__((noreturn));
extern void __gnat_rcheck_SE_Explicit_Raise(void *, int)
    __attribute__((noreturn));

void *malloc(usize count)
{
    void *result;
    enum allocator_status status = allocator_reserve(count, &result);
    if (status == ALLOCATOR_INVALID)
        __gnat_rcheck_PE_Explicit_Raise((void *)"allocator metadata", 0);
    return status == ALLOCATOR_OK ? result : 0;
}

void *__gnat_malloc(usize count)
{
    void *result;
    enum allocator_status status = allocator_reserve(count, &result);
    if (status == ALLOCATOR_EXHAUSTED)
        __gnat_rcheck_SE_Explicit_Raise((void *)"dynamic allocation", 0);
    if (status != ALLOCATOR_OK)
        __gnat_rcheck_PE_Explicit_Raise((void *)"allocator metadata", 0);
    return result;
}

void free(void *object)
{
    if (allocator_release(object) != ALLOCATOR_OK)
        __gnat_rcheck_PE_Explicit_Raise((void *)"invalid deallocation", 0);
}

void __gnat_free(void *object)
{
    free(object);
}
#endif
