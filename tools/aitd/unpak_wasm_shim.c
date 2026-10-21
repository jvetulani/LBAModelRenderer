/* Tiny allocator and C runtime surface for the browser's AITD PAK decoder.
 * Reset before each entry; the caller owns the input and output allocations. */
#include <stddef.h>

extern unsigned char __heap_base;
static unsigned int next_byte;

void reset_heap(void) { next_byte = (unsigned int)&__heap_base; }
void *malloc(size_t size) {
    unsigned int result = (next_byte + 7u) & ~7u;
    next_byte = result + (unsigned int)size;
    return (void *)result;
}
void free(void *ptr) { (void)ptr; }
void *memcpy(void *dest, const void *source, size_t size) {
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)source;
    for (size_t i = 0; i < size; ++i) d[i] = s[i];
    return dest;
}
void *memset(void *dest, int value, size_t size) {
    unsigned char *d = (unsigned char *)dest;
    for (size_t i = 0; i < size; ++i) d[i] = (unsigned char)value;
    return dest;
}

#define AITD_WASM 1
#include "unpak.c"
