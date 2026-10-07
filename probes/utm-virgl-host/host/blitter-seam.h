/* SPDX-License-Identifier: BSD-2-Clause */
/* EmberBSD, AI-assisted seam for the actual complete fini body only. */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
struct hash_entry { int unused; };
static struct {
    bool initialised;
    void *gl_context;
    void *blit_programs;
} vrend_blit_ctx;
static unsigned checks, failures, destroys, tables;
static int owned_context, owned_table;
static void check(bool ok) { checks++; if (!ok) failures++; }
static void destroy(void *context)
{
    check(context == &owned_context);
    destroys++;
}
static const struct { void (*destroy_gl_context)(void *); } callbacks = {destroy};
static const __typeof__(callbacks) *vrend_clicbs = &callbacks;
static void delete_program_cb(struct hash_entry *entry) { (void)entry; }
static void _mesa_hash_table_u64_destroy(void *table, void (*callback)(struct hash_entry *))
{
    check(table == &owned_table && callback == delete_program_cb);
    tables++;
}
