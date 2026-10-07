/* SPDX-License-Identifier: BSD-2-Clause
 * Origin: EmberBSD, AI-assisted actual-source bounds contract.
 */
#include <inttypes.h>
#include <stdio.h>
#include "pipe/p_state.h"
#include "util/u_format.h"
#include "util/u_math.h"
#include "vrend_iov.h"
/* Replace only the upstream logging/abort boundary; assertions still fail. */
void _debug_assert_fail(const char *expr, const char *file, unsigned line,
                        const char *function)
{
    fprintf(stderr, "%s:%u:%s: Assertion `%s' failed.\n", file, line, function, expr);
    abort();
}
/* GL-free seam: production functions access only this base member.
 * Actual pipe_resource, pipe_box and transfer_info definitions are included.
 * No renderer, GL dispatch, resource validation or transfer copy is modeled.
 */
typedef unsigned int GLuint;
struct vrend_resource { struct pipe_resource base; };
_Static_assert(sizeof(GLuint) == sizeof(uint32_t), "32-bit GL size required");
_Static_assert(sizeof(size_t) == sizeof(uint64_t), "64-bit host required");
#include "renderer.inc"

static unsigned cases, failures;
static void check(const char *name, enum pipe_format format,
                  unsigned width, unsigned height, unsigned depth,
                  int bw, int bh, int bd, unsigned level,
                  uint32_t stride, uint32_t layer, uint64_t offset,
                  size_t len0, size_t len1, bool expected, uint64_t span)
{
    struct vrend_resource res = { .base = { .format = format,
        .width0 = width, .height0 = height, .depth0 = depth,
        .target = depth > 1 ? PIPE_TEXTURE_3D : height > 1 ? PIPE_TEXTURE_2D : PIPE_BUFFER } };
    struct pipe_box box = { .width = bw, .height = bh, .depth = bd };
    struct vrend_transfer_info info = { .box = &box, .level = level,
        .stride = stride, .layer_stride = layer, .offset = offset };
    /* Ordinary regions have real small backing. Large cases use length-only
     * metadata; these bounds functions never dereference or copy any region.
     */
    unsigned char backing[2][256];
    struct iovec iov[2] = {
        { len0 <= sizeof(backing[0]) ? backing[0] : NULL, len0 },
        { len1 <= sizeof(backing[1]) ? backing[1] : NULL, len1 }
    };
    bool actual = check_iov_bounds(&res, &info, iov, 2);
    uint64_t actual_span = vrend_transfer_size(&res, &info, stride, layer);
    cases++;
    if (actual != expected || (span && actual_span != span)) {
        failures++;
        printf("FAIL: %s accepted=%d expected=%d span=%" PRIu64 "\n",
               name, actual, expected, actual_span);
    } else printf("PASS: %s\n", name);
}
#define C(name,fmt,w,h,d,bw,bh,bd,level,s,l,o,a,b,e,span) \
    check(name,PIPE_FORMAT_##fmt,w,h,d,bw,bh,bd,level,s,l,o,a,b,e,span)
/* These observations document separate unfixed arithmetic, not acceptance. */
static int limits(void)
{
    size_t row = util_format_get_stride(PIPE_FORMAT_R8G8B8A8_UNORM, 1073741825U);
    struct vrend_resource res = { .base = { .format = PIPE_FORMAT_R8G8B8A8_UNORM,
        .width0 = 1073741825U, .height0 = 2 } };
    struct pipe_box box = { .width = 1, .height = 2, .depth = 1 };
    struct vrend_transfer_info info = { .box = &box };
    unsigned char backing[8];
    struct iovec iov[2] = { { backing, sizeof(backing) }, { NULL, 0 } };
    bool default_row = check_iov_bounds(&res, &info, iov, 2);
    printf("LIMIT: default row unsigned product: stride=%zu (mathematical 4294967300), accepted=%d\n", row, default_row);
    box.width = 1073741825;
    box.height = 1;
    info.stride = 4;
    info.layer_stride = 4;
    iov[0].iov_base = NULL;
    iov[0].iov_len = 4294967300ULL;
    bool explicit_row = check_iov_bounds(&res, &info, iov, 2);
    printf("LIMIT: explicit row minimum unsigned product: stride=4, accepted=%d\n", explicit_row);
    res.base.format = PIPE_FORMAT_R8_UNORM;
    res.base.width0 = 16;
    res.base.height0 = 1;
    box.width = 16;
    info.stride = 16;
    info.layer_stride = 16;
    info.offset = UINT64_MAX - 8;
    iov[0].iov_len = SIZE_MAX;
    bool offset_add = check_iov_bounds(&res, &info, iov, 2);
    printf("LIMIT: offset+span unsigned overflow: offset=UINT64_MAX-8, span=16, accepted=%d\n", offset_add);
    iov[1].iov_len = 17;
    size_t total = vrend_get_iovec_size(iov, 2);
    printf("LIMIT: IOV size_t overflow: SIZE_MAX+17 becomes %zu\n", total);
    return row == 4 && default_row && explicit_row && offset_add && total == 16 ? 0 : 1;
}
int main(int argc, char **argv)
{
    if (argc == 2 && strcmp(argv[1], "limits") == 0) return limits();
    if (argc != 1) return 2;
    C("span-above-4GiB-short-backing",R8_UNORM,16,1,3,16,1,3,0,16,2147483648U,0,16,0,false,4294967312ULL);
    C("iov-above-4GiB-offset",R8_UNORM,16,1,1,16,1,1,0,16,16,4294967296ULL,UINT32_MAX,17,true,16);
    C("default-layer-above-UINT32_MAX",R8_UNORM,65536,65536,1,1,1,1,0,0,0,0,1,0,false,0);
    C("explicit-layer-min-above-UINT32_MAX",R8_UNORM,65536,65536,1,1,65536,1,0,65536,16,0,UINT32_MAX,0,false,4294901761ULL);
    C("buffer-exact-end",R8_UNORM,16,1,1,16,1,1,0,0,0,3,7,12,true,16);
    C("buffer-one-byte-short",R8_UNORM,16,1,1,16,1,1,0,0,0,3,7,11,false,16);
    C("offset-past-iov",R8_UNORM,1,1,1,1,1,1,0,0,0,17,16,0,false,1);
    C("rgba-exact-end",R8G8B8A8_UNORM,4,3,1,4,3,1,0,16,48,0,48,0,true,48);
    C("rgba-one-byte-short",R8G8B8A8_UNORM,4,3,1,4,3,1,0,16,48,0,47,0,false,48);
    C("rgba-row-min",R8G8B8A8_UNORM,4,3,1,4,3,1,0,15,48,0,100,0,false,46);
    C("rgba-layer-min",R8G8B8A8_UNORM,4,3,1,4,3,1,0,16,47,0,100,0,false,48);
    C("rgba-padded",R8G8B8A8_UNORM,4,3,2,4,3,2,0,32,128,0,208,0,true,208);
    C("rgba-padded-short",R8G8B8A8_UNORM,4,3,2,4,3,2,0,32,128,0,207,0,false,208);
    C("rgba-default",R8G8B8A8_UNORM,4,3,1,4,3,1,0,0,0,0,48,0,true,0);
    C("mip-default",R8G8B8A8_UNORM,8,8,1,4,4,1,1,0,0,0,64,0,true,0);
    C("dxt1-odd-block-exact",DXT1_RGB,7,5,1,7,5,1,0,16,32,0,32,0,true,32);
    C("dxt1-odd-block-short",DXT1_RGB,7,5,1,7,5,1,0,16,32,0,31,0,false,32);
    C("dxt1-row-min",DXT1_RGB,7,5,1,7,5,1,0,15,32,0,100,0,false,31);
    C("dxt1-layer-min",DXT1_RGB,7,5,1,7,5,1,0,16,31,0,100,0,false,32);
    C("dxt5-block",DXT5_RGBA,5,5,1,5,5,1,0,32,64,0,64,0,true,64);
    C("zero-box-helper-fallback",R8_UNORM,1,1,1,0,0,0,0,1,1,0,1,0,true,1);
    C("default-layer-UINT32_MAX",R8_UNORM,UINT32_MAX,1,1,1,1,1,0,0,0,0,1,0,true,0);
    C("large-iov-short-transfer",R8_UNORM,16,1,1,16,1,1,0,16,16,0,UINT32_MAX,1,true,16);
    printf("%u cases, %u failed\n", cases, failures);
    return failures ? 1 : 0;
}
