/* SPDX-License-Identifier: BSD-2-Clause */
/* Origin: EmberBSD, AI-assisted full-renderer command-result regression. */
#include <virgl_protocol.h>

static void
check_decoder_results(void)
{
    struct command_case {
        const char *name;
        uint32_t words[4];
        int count;
        int expected;
    } cases[] = {
        {"NOP", {VIRGL_CCMD_NOP}, 1, 0},
        {"opaque END_TRANSFERS padding",
            {(2u << 16) | VIRGL_CCMD_END_TRANSFERS, UINT32_MAX,
             UINT32_MAX, VIRGL_CCMD_NOP}, 4, 0},
        {"missing payload", {(1u << 16) | VIRGL_CCMD_NOP}, 1, EINVAL},
        {"truncated after valid command",
            {VIRGL_CCMD_NOP, (2u << 16) | VIRGL_CCMD_NOP, 0}, 3, EINVAL},
        {"maximum payload absent", {(65535u << 16) | VIRGL_CCMD_NOP}, 1, EINVAL},
        {"unknown opcode", {255}, 1, EINVAL},
    };
    unsigned failures = 0;
    for (unsigned i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        /* A buffer error poisons its context; each case owns a fresh one. */
        const uint32_t id = 100 + i;
        if (virgl_renderer_context_create(id, 7, "decoder"))
            die("decoder context creation");
        int result = virgl_renderer_submit_cmd(cases[i].words, id, cases[i].count);
        printf("decoder %s: result=%d expected=%d\n",
            cases[i].name, result, cases[i].expected);
        if (result != cases[i].expected) failures++;
        virgl_renderer_context_destroy(id);
    }
    printf("decoder: 6 cases, %u failures\n", failures);
    if (failures) die("decoder returned incorrect command result");
}
