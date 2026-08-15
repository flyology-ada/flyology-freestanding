/* SPDX-License-Identifier: MIT OR Apache-2.0 */

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum {
    ALIGNMENT = 16,
    CAPACITY = 65536,
    THREADS = 8,
    RESERVATIONS = 128
};

struct allocation {
    uintptr_t start;
    size_t size;
};

static pthread_mutex_t runtime_lock = PTHREAD_MUTEX_INITIALIZER;
static struct allocation allocations[THREADS][RESERVATIONS];
static size_t wave_arrived;
static unsigned char wave_released;

extern void *flyology_allocator_test_reserve(size_t);
extern int flyology_allocator_test_release(void *);
extern void flyology_allocator_test_reset(void);
extern size_t flyology_allocator_test_live(void);
extern size_t flyology_allocator_test_bytes(void);

void flyology_rts_lock_acquire(void)
{
    if (pthread_mutex_lock(&runtime_lock) != 0) {
        fputs("allocator test failed: mutex lock\n", stderr);
        abort();
    }
}

void flyology_rts_lock_release(void)
{
    if (pthread_mutex_unlock(&runtime_lock) != 0) {
        fputs("allocator test failed: mutex unlock\n", stderr);
        abort();
    }
}

static void fail(const char *message)
{
    fprintf(stderr, "allocator test failed: %s\n", message);
    exit(1);
}

static size_t aligned_size(size_t count)
{
    if (count == 0)
        return ALIGNMENT;
    return ((count - 1) / ALIGNMENT + 1) * ALIGNMENT;
}

static void wait_for_release(void)
{
    __atomic_add_fetch(&wave_arrived, 1, __ATOMIC_ACQ_REL);
    while (__atomic_load_n(&wave_released, __ATOMIC_ACQUIRE) == 0) {
    }
}

static void *worker(void *argument)
{
    size_t thread = (size_t)(uintptr_t)argument;
    size_t index;
    for (index = 0; index < RESERVATIONS; ++index) {
        size_t request = (thread * 7 + index * 11) % 31;
        void *result = flyology_allocator_test_reserve(request);
        if (result == 0)
            fail("unexpected concurrent exhaustion");
        allocations[thread][index].start = (uintptr_t)result;
        allocations[thread][index].size = aligned_size(request);
    }
    wait_for_release();
    for (index = 0; index < RESERVATIONS; ++index)
        if (!flyology_allocator_test_release(
              (void *)allocations[thread][index].start))
            fail("concurrent release rejected");
    return 0;
}

static void check_pairwise_disjoint(void)
{
    size_t thread;
    size_t index;
    size_t other_thread;
    size_t other_index;
    for (thread = 0; thread < THREADS; ++thread) {
        for (index = 0; index < RESERVATIONS; ++index) {
            struct allocation current = allocations[thread][index];
            if (current.start % ALIGNMENT != 0)
                fail("misaligned concurrent result");
            for (other_thread = thread; other_thread < THREADS;
                 ++other_thread) {
                size_t first_index = other_thread == thread ? index + 1 : 0;
                for (other_index = first_index;
                     other_index < RESERVATIONS; ++other_index) {
                    struct allocation other =
                        allocations[other_thread][other_index];
                    if (current.start < other.start + other.size &&
                        other.start < current.start + current.size)
                        fail("overlapping concurrent allocations");
                }
            }
        }
    }
}

int main(void)
{
    pthread_t threads[THREADS];
    size_t thread;
    void *first;
    void *middle;
    void *last;
    void *reused;
    void *whole;

    flyology_allocator_test_reset();
    first = flyology_allocator_test_reserve(0);
    middle = flyology_allocator_test_reserve(31);
    last = flyology_allocator_test_reserve(1);
    if (first == 0 || middle == 0 || last == 0 ||
        (uintptr_t)middle - (uintptr_t)first != ALIGNMENT ||
        (uintptr_t)last - (uintptr_t)middle != 2 * ALIGNMENT ||
        flyology_allocator_test_live() != 3 ||
        flyology_allocator_test_bytes() != 4 * ALIGNMENT)
        fail("initial allocation geometry");
    if (!flyology_allocator_test_release(middle))
        fail("middle release rejected");
    reused = flyology_allocator_test_reserve(32);
    if (reused != middle)
        fail("first-fit hole was not reused");
    if (flyology_allocator_test_release((unsigned char *)reused + 1) ||
        flyology_allocator_test_live() != 3)
        fail("interior pointer was accepted");
    if (!flyology_allocator_test_release(reused) ||
        flyology_allocator_test_release(reused))
        fail("double-free contract");
    if (!flyology_allocator_test_release(first) ||
        !flyology_allocator_test_release(last) ||
        !flyology_allocator_test_release(0) ||
        flyology_allocator_test_live() != 0 ||
        flyology_allocator_test_bytes() != 0)
        fail("complete release accounting");

    whole = flyology_allocator_test_reserve(CAPACITY);
    if (whole == 0 || flyology_allocator_test_reserve(1) != 0 ||
        flyology_allocator_test_reserve(SIZE_MAX) != 0 ||
        flyology_allocator_test_live() != 1 ||
        flyology_allocator_test_bytes() != CAPACITY)
        fail("capacity and rejection boundary");
    if (!flyology_allocator_test_release(whole) ||
        flyology_allocator_test_live() != 0 ||
        flyology_allocator_test_bytes() != 0)
        fail("whole-pool reclamation");

    wave_arrived = 0;
    wave_released = 0;
    for (thread = 0; thread < THREADS; ++thread)
        if (pthread_create(&threads[thread], 0, worker,
                           (void *)(uintptr_t)thread) != 0)
            fail("pthread_create");
    while (__atomic_load_n(&wave_arrived, __ATOMIC_ACQUIRE) != THREADS) {
    }
    if (flyology_allocator_test_live() != THREADS * RESERVATIONS)
        fail("concurrent live count");
    check_pairwise_disjoint();
    __atomic_store_n(&wave_released, 1, __ATOMIC_RELEASE);
    for (thread = 0; thread < THREADS; ++thread)
        if (pthread_join(threads[thread], 0) != 0)
            fail("pthread_join");
    if (flyology_allocator_test_live() != 0 ||
        flyology_allocator_test_bytes() != 0)
        fail("concurrent reclamation leak");

    whole = flyology_allocator_test_reserve(CAPACITY);
    if (whole == 0 || !flyology_allocator_test_release(whole))
        fail("fragmented pool did not become whole");

    puts("FLYOLOGY:RTS:ALLOCATOR:PASS");
    return 0;
}
