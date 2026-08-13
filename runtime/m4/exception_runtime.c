/* SPDX-License-Identifier: MIT OR Apache-2.0 */

/* This file implements the language-specific side of the public, generic
   two-phase unwind ABI.  It is original Flyology code derived from the ABI
   specification and owned compiler-output probes; it contains no GNAT RTS
   source. */

#include <unwind.h>

typedef __UINT8_TYPE__ u8;
typedef __UINT64_TYPE__ u64;
typedef __INT64_TYPE__ i64;
typedef __UINTPTR_TYPE__ uptr;
typedef __SIZE_TYPE__ usize;

enum { EXCEPTION_CAPACITY = 32, ALLOCATION_CAPACITY = 65536 };

struct flyology_exception {
    struct _Unwind_Exception unwind;
    void *identity;
    u8 occupied;
};

u8 constraint_error;
u8 program_error;
u8 storage_error;
u8 tasking_error;
static u8 abort_signal;
u8 __gnat_others_value;
u8 __gnat_all_others_value;

static struct flyology_exception exceptions[EXCEPTION_CAPACITY]
    __attribute__((aligned(16)));
static u8 allocation_pool[ALLOCATION_CAPACITY] __attribute__((aligned(16)));
static usize allocation_used;
static const char *last_personality = "personality not called";

extern const u8 __eh_frame_runtime_start[];
extern const u8 __eh_frame_probe_start[];
extern void __register_frame(const void *);
extern void __gnat_last_chance_handler(void *, int) __attribute__((noreturn));

static u64 read_uleb(const u8 **cursor)
{
    const u8 *p = *cursor;
    u64 value = 0;
    unsigned shift = 0;
    for (;;) {
        u8 byte = *p++;
        value |= (u64)(byte & 0x7fU) << shift;
        if ((byte & 0x80U) == 0)
            break;
        shift += 7;
        if (shift >= 64)
            __gnat_last_chance_handler((void *)"invalid ULEB128", 0);
    }
    *cursor = p;
    return value;
}

static i64 read_sleb(const u8 **cursor)
{
    const u8 *p = *cursor;
    u64 value = 0;
    unsigned shift = 0;
    u8 byte;
    do {
        byte = *p++;
        value |= (u64)(byte & 0x7fU) << shift;
        shift += 7;
        if (shift >= 64 && (byte & 0x80U) != 0)
            __gnat_last_chance_handler((void *)"invalid SLEB128", 0);
    } while ((byte & 0x80U) != 0);
    if (shift < 64 && (byte & 0x40U) != 0)
        value |= (~(u64)0) << shift;
    *cursor = p;
    return (i64)value;
}

static u64 read_unsigned(const u8 **cursor, unsigned bytes)
{
    const u8 *p = *cursor;
    u64 value = 0;
    unsigned index;
    for (index = 0; index < bytes; ++index)
        value |= (u64)p[index] << (index * 8);
    *cursor = p + bytes;
    return value;
}

static i64 sign_extend(u64 value, unsigned bits)
{
    u64 sign = (u64)1 << (bits - 1);
    return (i64)((value ^ sign) - sign);
}

static uptr read_encoded(const u8 **cursor, u8 encoding, uptr region_start)
{
    const u8 *field = *cursor;
    uptr value;
    switch (encoding & 0x0fU) {
    case 0x00: value = (uptr)read_unsigned(cursor, sizeof(uptr)); break;
    case 0x01: value = (uptr)read_uleb(cursor); break;
    case 0x02: value = (uptr)read_unsigned(cursor, 2); break;
    case 0x03: value = (uptr)read_unsigned(cursor, 4); break;
    case 0x04: value = (uptr)read_unsigned(cursor, 8); break;
    case 0x09: value = (uptr)read_sleb(cursor); break;
    case 0x0a: value = (uptr)sign_extend(read_unsigned(cursor, 2), 16); break;
    case 0x0b: value = (uptr)sign_extend(read_unsigned(cursor, 4), 32); break;
    case 0x0c: value = (uptr)read_unsigned(cursor, 8); break;
    default: __gnat_last_chance_handler((void *)"unsupported EH encoding", 0);
    }
    switch (encoding & 0x70U) {
    case 0x00: break;
    case 0x10: value += (uptr)field; break;
    case 0x20: value += region_start; break;
    default: __gnat_last_chance_handler((void *)"unsupported EH base", 0);
    }
    if ((encoding & 0x80U) != 0)
        value = *(const uptr *)value;
    return value;
}

static unsigned encoded_size(u8 encoding)
{
    switch (encoding & 0x0fU) {
    case 0x00: return sizeof(uptr);
    case 0x02: case 0x0a: return 2;
    case 0x03: case 0x0b: return 4;
    case 0x04: case 0x0c: return 8;
    default: return 0;
    }
}

static void exception_cleanup(_Unwind_Reason_Code reason,
                              struct _Unwind_Exception *object)
{
    struct flyology_exception *exception =
        (struct flyology_exception *)object;
    (void)reason;
    __atomic_store_n(&exception->occupied, 0, __ATOMIC_RELEASE);
}

static struct flyology_exception *reserve_exception(void *identity)
{
    unsigned index;
    for (index = 0; index < EXCEPTION_CAPACITY; ++index) {
        u8 expected = 0;
        if (__atomic_compare_exchange_n(&exceptions[index].occupied,
                                        &expected, 1, 0,
                                        __ATOMIC_ACQ_REL,
                                        __ATOMIC_ACQUIRE)) {
            struct flyology_exception *result = &exceptions[index];
            result->identity = identity;
            result->unwind.exception_class = 0x464c594f41444100ULL;
            result->unwind.exception_cleanup = exception_cleanup;
            result->unwind.private_1 = 0;
            result->unwind.private_2 = 0;
            return result;
        }
    }
    __gnat_last_chance_handler((void *)"exception pool exhausted", 0);
}

static void raise_identity(void *identity) __attribute__((noreturn));
static void raise_identity(void *identity)
{
    struct flyology_exception *exception = reserve_exception(identity);
    _Unwind_Reason_Code result = _Unwind_RaiseException(&exception->unwind);
    if (result == _URC_NO_REASON)
        last_personality = "unwinder returned no reason";
    else if (result == _URC_FOREIGN_EXCEPTION_CAUGHT)
        last_personality = "unwinder foreign exception result";
    else if (result == _URC_NORMAL_STOP)
        last_personality = "unwinder normal stop";
    else if (result == _URC_END_OF_STACK)
        last_personality = "unwinder reached end of stack";
    else if (result == _URC_FATAL_PHASE1_ERROR)
        last_personality = "unwinder phase one failure";
    else if (result == _URC_FATAL_PHASE2_ERROR)
        last_personality = "unwinder phase two failure";
    else if (result == _URC_HANDLER_FOUND)
        last_personality = "unwinder leaked handler result";
    else if (result == _URC_INSTALL_CONTEXT)
        last_personality = "unwinder leaked install result";
    else if (result == _URC_CONTINUE_UNWIND)
        last_personality = "unwinder leaked continue result";
    __gnat_last_chance_handler((void *)last_personality, 0);
}

void flyology_exception_initialize(void)
{
    __register_frame(__eh_frame_runtime_start);
    __register_frame(__eh_frame_probe_start);
}

void __gnat_rcheck_PE_Explicit_Raise(void *location, int line)
{
    (void)location;
    (void)line;
    raise_identity(&program_error);
}

void __gnat_rcheck_CE_Explicit_Raise(void *location, int line)
{
    (void)location;
    (void)line;
    raise_identity(&constraint_error);
}

void __gnat_rcheck_CE_Access_Check(void *location, int line)
{
    __gnat_rcheck_CE_Explicit_Raise(location, line);
}

void __gnat_rcheck_CE_Index_Check(void *location, int line)
{
    __gnat_rcheck_CE_Explicit_Raise(location, line);
}

void __gnat_rcheck_CE_Invalid_Data(void *location, int line)
{
    __gnat_rcheck_CE_Explicit_Raise(location, line);
}

void __gnat_rcheck_CE_Overflow_Check(void *location, int line)
{
    __gnat_rcheck_CE_Explicit_Raise(location, line);
}

void __gnat_rcheck_CE_Range_Check(void *location, int line)
{
    __gnat_rcheck_CE_Explicit_Raise(location, line);
}

void __gnat_rcheck_SE_Explicit_Raise(void *location, int line)
{
    (void)location;
    (void)line;
    raise_identity(&storage_error);
}

void __gnat_rcheck_TE_Explicit_Raise(void *location, int line)
{
    (void)location;
    (void)line;
    raise_identity(&tasking_error);
}

void flyology_raise_abort(void) __attribute__((noreturn));
void flyology_raise_abort(void)
{
    raise_identity(&abort_signal);
}

_Unwind_Reason_Code __gnat_personality_v0
  (int version, _Unwind_Action actions, u64 exception_class,
   struct _Unwind_Exception *exception_object,
   struct _Unwind_Context *context)
{
    const u8 *lsda;
    const u8 *cursor;
    const u8 *type_base = 0;
    const u8 *action_base;
    uptr region_start;
    uptr ip;
    uptr landing = 0;
    i64 selector = 0;
    u8 encoding;
    u8 type_encoding;
    struct flyology_exception *exception;
    (void)exception_class;

    if (version != 1)
        return _URC_FATAL_PHASE1_ERROR;
    last_personality = "personality entered";
    lsda = (const u8 *)_Unwind_GetLanguageSpecificData(context);
    if (lsda == 0)
        return _URC_CONTINUE_UNWIND;
    region_start = (uptr)_Unwind_GetRegionStart(context);
    ip = (uptr)_Unwind_GetIP(context) - 1;
    cursor = lsda;

    encoding = *cursor++;
    if (encoding != 0xff)
        (void)read_encoded(&cursor, encoding, region_start);
    type_encoding = *cursor++;
    if (type_encoding != 0xff) {
        u64 offset = read_uleb(&cursor);
        type_base = cursor + offset;
    }
    encoding = *cursor++;
    if (encoding != 0x01)
        __gnat_last_chance_handler((void *)"unsupported call-site encoding", 0);
    {
        u64 table_length = read_uleb(&cursor);
        const u8 *call_end = cursor + table_length;
        while (cursor < call_end) {
            uptr start = read_encoded(&cursor, encoding, region_start);
            uptr length = read_encoded(&cursor, encoding, region_start);
            uptr pad = read_encoded(&cursor, encoding, region_start);
            u64 action = read_uleb(&cursor);
            if (ip >= region_start + start && ip < region_start + start + length) {
                if (pad == 0)
                    return _URC_CONTINUE_UNWIND;
                landing = region_start + pad;
                selector = (i64)action;
                break;
            }
        }
        action_base = call_end;
    }
    if (landing == 0)
        return _URC_CONTINUE_UNWIND;
    last_personality = "personality found landing";

    exception = (struct flyology_exception *)exception_object;
    if (selector != 0) {
        const u8 *action = action_base + selector - 1;
        int matched = 0;
        for (;;) {
            i64 filter = read_sleb(&action);
            const u8 *next_field = action;
            i64 next = read_sleb(&action);
            if (filter > 0 && type_base != 0) {
                unsigned size = encoded_size(type_encoding);
                const u8 *type_cursor;
                void *identity;
                if (size == 0)
                    __gnat_last_chance_handler((void *)"variable EH type", 0);
                type_cursor = type_base - (usize)filter * size;
                identity = (void *)read_encoded(&type_cursor, type_encoding,
                                                region_start);
                if (identity == exception->identity ||
                    identity == &__gnat_others_value ||
                    identity == &__gnat_all_others_value) {
                    matched = 1;
                    selector = filter;
                    break;
                }
            }
            if (next == 0)
                break;
            action = next_field + next;
        }
        if (!matched)
            return _URC_CONTINUE_UNWIND;
        last_personality = "personality matched handler";
        if ((actions & _UA_SEARCH_PHASE) != 0)
            return _URC_HANDLER_FOUND;
        if ((actions & _UA_HANDLER_FRAME) == 0)
            return _URC_CONTINUE_UNWIND;
    } else if ((actions & _UA_SEARCH_PHASE) != 0) {
        return _URC_CONTINUE_UNWIND;
    }

    if ((actions & _UA_CLEANUP_PHASE) == 0)
        return _URC_CONTINUE_UNWIND;
    _Unwind_SetGR(context, __builtin_eh_return_data_regno(0),
                  (uptr)exception_object);
    _Unwind_SetGR(context, __builtin_eh_return_data_regno(1), (uptr)selector);
    _Unwind_SetIP(context, landing);
    return _URC_INSTALL_CONTEXT;
}

void *__gnat_begin_handler_v1(struct _Unwind_Exception *exception)
{
    return exception;
}

void __gnat_end_handler_v1(struct _Unwind_Exception *exception,
                           void *cookie,
                           struct _Unwind_Exception *propagating)
{
    (void)cookie;
    if (propagating != exception)
        _Unwind_DeleteException(exception);
}

void __gnat_reraise_zcx(struct _Unwind_Exception *exception)
{
    (void)_Unwind_Resume_or_Rethrow(exception);
    __gnat_last_chance_handler((void *)"Ada re-raise returned", 0);
}

#ifndef FLYOLOGY_RUNTIME_MEMORY_EXTERNAL
void *memcpy(void *destination, const void *source, usize count)
{
    u8 *to = (u8 *)destination;
    const u8 *from = (const u8 *)source;
    usize index;
    for (index = 0; index < count; ++index)
        to[index] = from[index];
    return destination;
}

void *memset(void *destination, int value, usize count)
{
    u8 *to = (u8 *)destination;
    usize index;
    for (index = 0; index < count; ++index)
        to[index] = (u8)value;
    return destination;
}
#endif

usize strlen(const char *text)
{
    usize length = 0;
    while (text[length] != 0)
        ++length;
    return length;
}

void *malloc(usize count)
{
    usize aligned = (count + 15U) & ~(usize)15U;
    usize start = __atomic_fetch_add(&allocation_used, aligned, __ATOMIC_ACQ_REL);
    if (aligned < count || start > ALLOCATION_CAPACITY ||
        aligned > ALLOCATION_CAPACITY - start)
        return 0;
    return allocation_pool + start;
}

void *__gnat_malloc(usize count)
{
    void *result = malloc(count);
    if (result == 0)
        __gnat_rcheck_SE_Explicit_Raise((void *)"dynamic allocation", 0);
    return result;
}

void free(void *object)
{
    (void)object;
}

void abort(void)
{
    __gnat_last_chance_handler((void *)"generic unwinder abort", 0);
}
