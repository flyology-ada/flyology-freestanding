/* SPDX-License-Identifier: MIT OR Apache-2.0 */

#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

enum {
    ALIGNMENT = 16,
    CAPACITY = 65536,
    THREADS = 8,
    RESERVATIONS = 256
};

struct allocation {
    uintptr_t start;
    size_t size;
};

static struct allocation allocations[THREADS][RESERVATIONS];
static size_t exhaustion_successes[THREADS];

extern void *flyology_allocator_test_reserve(size_t);
extern void flyology_allocator_test_reset(void);
extern size_t flyology_allocator_test_used(void);
extern void flyology_allocator_test_set_used(size_t);
extern void flyology_allocator_test_gate(size_t);
extern size_t flyology_allocator_test_retries(void);

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

static void *worker(void *argument)
{
    size_t thread = (size_t)(uintptr_t)argument;
    size_t index;
    for (index = 0; index < RESERVATIONS; ++index) {
        size_t request = (thread * 7 + index * 11) % 31;
        void *result = flyology_allocator_test_reserve(request);
        if (result == 0)
            fail("unexpected contention exhaustion");
        allocations[thread][index].start = (uintptr_t)result;
        allocations[thread][index].size = aligned_size(request);
    }
    return 0;
}

static void *exhaustion_worker(void *argument)
{
    size_t thread = (size_t)(uintptr_t)argument;
    exhaustion_successes[thread] =
        flyology_allocator_test_reserve(10000) != 0 ? 1 : 0;
    return 0;
}

int main(void)
{
    pthread_t threads[THREADS];
    size_t thread;
    size_t index;
    size_t other_thread;
    size_t other_index;
    void *first;
    void *second;
    size_t before;
    size_t expected_used = 0;
    size_t successes = 0;

    flyology_allocator_test_reset();
    first = flyology_allocator_test_reserve(0);
    second = flyology_allocator_test_reserve(0);
    if (first == 0 || second == 0 ||
        (uintptr_t)second - (uintptr_t)first != ALIGNMENT ||
        flyology_allocator_test_used() != 2 * ALIGNMENT)
        fail("zero-size reservation contract");

    flyology_allocator_test_reset();
    first = flyology_allocator_test_reserve(CAPACITY - ALIGNMENT);
    second = flyology_allocator_test_reserve(1);
    if (first == 0 || second == 0 ||
        flyology_allocator_test_used() != CAPACITY)
        fail("capacity boundary");
    before = flyology_allocator_test_used();
    if (flyology_allocator_test_reserve(1) != 0 ||
        flyology_allocator_test_reserve(SIZE_MAX) != 0 ||
        flyology_allocator_test_used() != before)
        fail("failed reservation changes cursor");

    flyology_allocator_test_set_used(1);
    if (flyology_allocator_test_reserve(1) != 0 ||
        flyology_allocator_test_used() != 1)
        fail("unaligned cursor is not rejected unchanged");

    flyology_allocator_test_reset();
    flyology_allocator_test_gate(THREADS);
    for (thread = 0; thread < THREADS; ++thread)
        if (pthread_create(&threads[thread], 0, worker,
                           (void *)(uintptr_t)thread) != 0)
            fail("pthread_create");
    for (thread = 0; thread < THREADS; ++thread)
        if (pthread_join(threads[thread], 0) != 0)
            fail("pthread_join");

    for (thread = 0; thread < THREADS; ++thread) {
        for (index = 0; index < RESERVATIONS; ++index) {
            struct allocation current = allocations[thread][index];
            expected_used += current.size;
            if (current.start % ALIGNMENT != 0)
                fail("misaligned result");
            for (other_thread = thread; other_thread < THREADS;
                 ++other_thread) {
                size_t first_index = other_thread == thread ? index + 1 : 0;
                for (other_index = first_index;
                     other_index < RESERVATIONS; ++other_index) {
                    struct allocation other =
                        allocations[other_thread][other_index];
                    if (current.start < other.start + other.size &&
                        other.start < current.start + current.size)
                        fail("overlapping concurrent reservations");
                }
            }
        }
    }
    if (flyology_allocator_test_used() != expected_used)
        fail("concurrent cursor accounting");
    if (flyology_allocator_test_retries() == 0)
        fail("CAS retry path was not exercised");

    flyology_allocator_test_reset();
    flyology_allocator_test_gate(THREADS);
    for (thread = 0; thread < THREADS; ++thread)
        if (pthread_create(&threads[thread], 0, exhaustion_worker,
                           (void *)(uintptr_t)thread) != 0)
            fail("exhaustion pthread_create");
    for (thread = 0; thread < THREADS; ++thread) {
        if (pthread_join(threads[thread], 0) != 0)
            fail("exhaustion pthread_join");
        successes += exhaustion_successes[thread];
    }
    if (successes != 6 || flyology_allocator_test_used() != 60000 ||
        flyology_allocator_test_retries() == 0)
        fail("concurrent exhaustion accounting");
    before = flyology_allocator_test_used();
    if (flyology_allocator_test_reserve(10000) != 0 ||
        flyology_allocator_test_used() != before)
        fail("terminal exhaustion changes cursor");

    puts("FLYOLOGY:M4:ALLOCATOR:PASS");
    return 0;
}
