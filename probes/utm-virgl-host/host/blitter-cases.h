/* SPDX-License-Identifier: BSD-2-Clause */
int main(void)
{
    vrend_blitter_fini();
    check(destroys == 0 && tables == 0);
    destroys = 0;
    vrend_blit_ctx.gl_context = &owned_context;
    vrend_blit_ctx.blit_programs = &owned_table;
    vrend_blit_ctx.initialised = true;
    vrend_blitter_fini();
    check(destroys == 1 && tables == 1);
    check(!vrend_blit_ctx.initialised && !vrend_blit_ctx.gl_context && !vrend_blit_ctx.blit_programs);
    vrend_blitter_fini();
    check(destroys == 1 && tables == 1);
    printf("blitter fini: %u checks, %u failures\n", checks, failures);
    return failures ? 1 : 0;
}
