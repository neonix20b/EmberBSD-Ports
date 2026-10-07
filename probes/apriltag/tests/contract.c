/* SPDX-License-Identifier: MIT */
#include <apriltag/apriltag.h>
#include <apriltag/apriltag_pose.h>
#include <apriltag/tag36h11.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void
require(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "AprilTag contract failed: %s\n", message);
        exit(1);
    }
}

/* Inverse image transform, independent of the detector and pose estimator. */
static image_u8_t *
render(const image_u8_t *tag, double scale, double angle, double cx, double cy)
{
    image_u8_t *image = image_u8_create(640, 480);
    require(image != NULL, "image allocation");
    memset(image->buf, 255, (size_t)image->stride * image->height);
    for (int y = 0; y < image->height; ++y) {
        for (int x = 0; x < image->width; ++x) {
            double dx = x + 0.5 - cx;
            double dy = y + 0.5 - cy;
            int tx = (int)floor((cos(angle)*dx + sin(angle)*dy)/scale + tag->width/2.0);
            int ty = (int)floor((-sin(angle)*dx + cos(angle)*dy)/scale + tag->height/2.0);
            if (tx >= 0 && ty >= 0 && tx < tag->width && ty < tag->height)
                image->buf[y * image->stride + x] = tag->buf[ty * tag->stride + tx];
        }
    }
    return image;
}

static void
pose_check(apriltag_detection_t *detection, double scale, double angle, double cx, double cy,
    int border_width)
{
    apriltag_detection_info_t info = {
        .det = detection, .tagsize = 0.16,
        .fx = 600, .fy = 600, .cx = 320, .cy = 240
    };
    apriltag_pose_t pose = { 0 };
    double error = estimate_tag_pose(&info, &pose);
    require(isfinite(error) && error < 1e-5, "pose reprojection/object error");
    require(pose.R != NULL && pose.t != NULL, "pose matrices");
    double z = info.fx * info.tagsize / (border_width * scale);
    double expected_t[3] = { (cx - info.cx) * z / info.fx, (cy - info.cy) * z / info.fy, z };
    double expected_r[9] = { cos(angle), -sin(angle), 0, sin(angle), cos(angle), 0, 0, 0, 1 };
    for (int row = 0; row < 3; ++row) {
        require(isfinite(MATD_EL(pose.t, row, 0)) &&
            fabs(MATD_EL(pose.t, row, 0) - expected_t[row]) < 0.005, "translation within 5 mm");
        for (int col = 0; col < 3; ++col) {
            require(isfinite(MATD_EL(pose.R, row, col)) &&
                fabs(MATD_EL(pose.R, row, col) - expected_r[row*3+col]) < 0.04,
                "rotation matrix within 0.04 per element");
        }
    }
    printf("pose: t=(%.5f, %.5f, %.5f) m error=%.9g\n",
        MATD_EL(pose.t, 0, 0), MATD_EL(pose.t, 1, 0), MATD_EL(pose.t, 2, 0), error);
    matd_destroy(pose.R);
    matd_destroy(pose.t);
}

static void
detect_check(apriltag_detector_t *detector, const image_u8_t *tag, unsigned id,
    double scale, double angle, double cx, double cy, int border_width)
{
    image_u8_t *image = render(tag, scale, angle, cx, cy);
    zarray_t *detections = apriltag_detector_detect(detector, image);
    require(detections != NULL && zarray_size(detections) == 1, "exactly one tag");
    apriltag_detection_t *detection;
    zarray_get(detections, 0, &detection);
    require(detection->id == (int)id && detection->hamming == 0, "known tag ID without bit correction");
    require(strcmp(detection->family->name, "tag36h11") == 0, "family identity");
    require(isfinite(detection->decision_margin) && detection->decision_margin > 30, "decision margin");
    require(fabs(detection->c[0] - cx) < 1.5 && fabs(detection->c[1] - cy) < 1.5,
        "detected center within 1.5 pixels");
    pose_check(detection, scale, angle, cx, cy, border_width);
    apriltag_detections_destroy(detections);
    image_u8_destroy(image);
}

int
main(void)
{
    apriltag_family_t *family = tag36h11_create();
    apriltag_detector_t *detector = apriltag_detector_create();
    require(family != NULL && detector != NULL, "detector allocation");
    apriltag_detector_add_family_bits(detector, family, 0);
    detector->nthreads = 2;
    detector->quad_decimate = 1;
    detector->refine_edges = true;
    image_u8_t *tag = apriltag_to_image(family, 42);
    require(tag != NULL && family->width_at_border == 8, "known family geometry");
    detect_check(detector, tag, 42, 20, 0, 320, 240, family->width_at_border);
    detect_check(detector, tag, 42, 18, 0.29, 345, 220, family->width_at_border);

    image_u8_t *blank = image_u8_create(640, 480);
    require(blank != NULL, "blank allocation");
    memset(blank->buf, 255, (size_t)blank->stride * blank->height);
    zarray_t *detections = apriltag_detector_detect(detector, blank);
    require(detections != NULL && zarray_size(detections) == 0, "blank image must have no tag");
    apriltag_detections_destroy(detections);
    image_u8_destroy(blank);

    /* A black square has tag-like edges but no valid tag36h11 code. */
    memset(tag->buf, 255, (size_t)tag->stride * tag->height);
    for (int y = 1; y < tag->height - 1; ++y)
        for (int x = 1; x < tag->width - 1; ++x)
            tag->buf[y * tag->stride + x] = 0;
    image_u8_t *invalid = render(tag, 20, 0.17, 320, 240);
    detections = apriltag_detector_detect(detector, invalid);
    require(detections != NULL && zarray_size(detections) == 0, "invalid code must have no tag");
    apriltag_detections_destroy(detections);
    image_u8_destroy(invalid);
    image_u8_destroy(tag);
    apriltag_detector_destroy(detector);
    tag36h11_destroy(family);
    puts("AprilTag: ID 42, transformed detection, numerical pose, blank and invalid code passed");
    return 0;
}
