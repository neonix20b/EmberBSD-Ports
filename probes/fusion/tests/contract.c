/* SPDX-License-Identifier: MIT */
#include <Fusion.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PI 3.14159265358979323846
#define RATE 100.0

static double max_norm_error;

static void
require(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(EXIT_FAILURE);
    }
}

static FusionVector
vector(double x, double y, double z)
{
    FusionVector result = { .axis = { (float)x, (float)y, (float)z } };
    return result;
}

static double
length(FusionVector v)
{
    return sqrt((double)v.axis.x * v.axis.x + (double)v.axis.y * v.axis.y +
        (double)v.axis.z * v.axis.z);
}

/* Independent Rz(yaw) Ry(pitch) Rx(roll), sensor-to-earth NWU quaternion. */
static FusionQuaternion
orientation(double roll, double pitch, double yaw)
{
    double r = roll * PI / 360.0, p = pitch * PI / 360.0;
    double y = yaw * PI / 360.0;
    FusionQuaternion q = { .element = {
        (float)(cos(r) * cos(p) * cos(y) + sin(r) * sin(p) * sin(y)),
        (float)(sin(r) * cos(p) * cos(y) - cos(r) * sin(p) * sin(y)),
        (float)(cos(r) * sin(p) * cos(y) + sin(r) * cos(p) * sin(y)),
        (float)(cos(r) * cos(p) * sin(y) - sin(r) * sin(p) * cos(y))
    } };
    return q;
}

/* Analytic transpose rotation: gravity/up and magnetic north in body axes. */
static void
sensors(double roll, double pitch, double yaw, FusionVector *acc, FusionVector *mag)
{
    double r = roll * PI / 180.0, p = pitch * PI / 180.0;
    double y = yaw * PI / 180.0;
    *acc = vector(-sin(p), cos(p) * sin(r), cos(p) * cos(r));
    *mag = vector(cos(y) * cos(p), cos(y) * sin(p) * sin(r) - sin(y) * cos(r),
        cos(y) * sin(p) * cos(r) + sin(y) * sin(r));
}

static FusionQuaternion
checked_quaternion(const FusionAhrs *ahrs)
{
    FusionQuaternion q = FusionAhrsGetQuaternion(ahrs);
    double norm = 0.0;
    int i;
    for (i = 0; i < 4; i++) {
        require(isfinite(q.array[i]), "finite quaternion");
        norm += (double)q.array[i] * q.array[i];
    }
    norm = fabs(sqrt(norm) - 1.0);
    require(norm < 0.001, "unit quaternion within default fast-sqrt tolerance");
    if (norm > max_norm_error)
        max_norm_error = norm;
    return q;
}

/* q and -q represent the same rotation. Normalize independently in double. */
static double
angle_error(FusionQuaternion actual, FusionQuaternion expected)
{
    double dot = 0.0, an = 0.0, en = 0.0;
    int i;
    for (i = 0; i < 4; i++) {
        dot += (double)actual.array[i] * expected.array[i];
        an += (double)actual.array[i] * actual.array[i];
        en += (double)expected.array[i] * expected.array[i];
    }
    dot = fabs(dot) / sqrt(an * en);
    require(isfinite(dot), "finite quaternion angular error");
    return 2.0 * acos(fmin(1.0, dot)) * 180.0 / PI;
}

static void
initialise(FusionAhrs *ahrs)
{
    FusionAhrsSettings settings = fusionAhrsDefaultSettings;
    settings.sampleRate = (float)RATE;
    settings.convention = FusionConventionNwu;
    settings.gain = 0.5f;
    FusionAhrsInitialise(ahrs);
    FusionAhrsSetSettings(ahrs, &settings);
}

static void
static_case(void)
{
    static const double poses[][3] = {
        { 0, 0, 0 }, { 30, -20, 45 }, { -40, 25, -60 }
    };
    size_t pose;
    for (pose = 0; pose < sizeof(poses) / sizeof(poses[0]); pose++) {
        FusionAhrs ahrs;
        FusionVector acc, mag;
        double error;
        int sample;
        initialise(&ahrs);
        sensors(poses[pose][0], poses[pose][1], poses[pose][2], &acc, &mag);
        for (sample = 0; sample < 2000; sample++) {
            FusionAhrsUpdate(&ahrs, vector(0, 0, 0), acc, mag);
            (void)checked_quaternion(&ahrs);
        }
        error = angle_error(checked_quaternion(&ahrs),
            orientation(poses[pose][0], poses[pose][1], poses[pose][2]));
        printf("static pose=%zu error_deg=%.8f linear_accel_g=%.8f\n", pose,
            error, length(FusionAhrsGetLinearAcceleration(&ahrs)));
        require(error < 0.25, "static orientation converges within 0.25 degrees");
        require(length(FusionAhrsGetLinearAcceleration(&ahrs)) < 0.003,
            "stationary linear acceleration below 0.003 g");
        require(!FusionAhrsGetFlags(&ahrs).startup, "static startup completed");
    }
}

static void
rotation_case(void)
{
    FusionAhrs ahrs;
    FusionVector acc, mag;
    double error, maximum = 0.0;
    int sample;
    initialise(&ahrs);
    FusionAhrsSkipStartup(&ahrs);
    /* Six-axis path: 90 degrees in one second without magnetic heading. */
    for (sample = 1; sample <= 100; sample++) {
        FusionAhrsUpdateNoMagnetometer(&ahrs, vector(0, 0, 90), vector(0, 0, 1));
        error = angle_error(checked_quaternion(&ahrs), orientation(0, 0, 0.9 * sample));
        require(error < 0.1, "six-axis known rotation within 0.1 degrees");
        if (error > maximum)
            maximum = error;
    }
    printf("six-axis max_error_deg=%.8f\n", maximum);
    initialise(&ahrs);
    FusionAhrsSkipStartup(&ahrs);
    maximum = 0.0;
    /* Nine-axis path: magnetic north rotates in body axes during a full turn.
     * Sensor values are at interval start; expected attitude is interval end. */
    for (sample = 1; sample <= 800; sample++) {
        sensors(0, 0, 0.45 * (sample - 1), &acc, &mag);
        FusionAhrsUpdate(&ahrs, vector(0, 0, 45), acc, mag);
        error = angle_error(checked_quaternion(&ahrs), orientation(0, 0, 0.45 * sample));
        require(error < 0.2, "nine-axis full turn within 0.2 degrees");
        if (error > maximum)
            maximum = error;
    }
    printf("nine-axis max_error_deg=%.8f\n", maximum);
}

static void
bias_case(void)
{
    FusionBias bias;
    FusionBiasSettings settings = fusionBiasDefaultSettings;
    FusionVector offset, corrected = vector(0, 0, 0);
    FusionVector measured = vector(0.6, -0.4, 0.8);
    FusionAhrs corrected_ahrs, raw_ahrs;
    double corrected_error, raw_error;
    int sample;
    FusionBiasInitialise(&bias);
    settings.sampleRate = (float)RATE;
    FusionBiasSetSettings(&bias, &settings);
    for (sample = 0; sample < 300; sample++)
        (void)FusionBiasUpdate(&bias, measured);
    require(length(FusionBiasGetOffset(&bias)) == 0.0,
        "bias waits for three stationary seconds");
    for (sample = 0; sample < 6000; sample++)
        corrected = FusionBiasUpdate(&bias, measured);
    offset = FusionBiasGetOffset(&bias);
    require(length(corrected) < 0.001, "stationary bias residual below 0.001 dps");
    printf("bias offset_dps=%.8f,%.8f,%.8f residual_dps=%.8f\n",
        offset.axis.x, offset.axis.y, offset.axis.z, length(corrected));
    for (sample = 0; sample < 100; sample++)
        (void)FusionBiasUpdate(&bias, vector(30.6, -0.4, 0.8));
    corrected = FusionBiasGetOffset(&bias);
    require(corrected.axis.x == offset.axis.x && corrected.axis.y == offset.axis.y &&
        corrected.axis.z == offset.axis.z, "motion must not be learned as bias");
    initialise(&corrected_ahrs);
    initialise(&raw_ahrs);
    FusionAhrsSkipStartup(&corrected_ahrs);
    FusionAhrsSkipStartup(&raw_ahrs);
    for (sample = 0; sample < 1000; sample++) {
        corrected = FusionBiasUpdate(&bias, measured);
        FusionAhrsUpdateNoMagnetometer(&corrected_ahrs, corrected, vector(0, 0, 1));
        FusionAhrsUpdateNoMagnetometer(&raw_ahrs, measured, vector(0, 0, 1));
        (void)checked_quaternion(&corrected_ahrs);
        (void)checked_quaternion(&raw_ahrs);
    }
    corrected_error = angle_error(checked_quaternion(&corrected_ahrs), orientation(0, 0, 0));
    raw_error = angle_error(checked_quaternion(&raw_ahrs), orientation(0, 0, 0));
    printf("bias attitude corrected_error_deg=%.8f raw_error_deg=%.8f\n",
        corrected_error, raw_error);
    require(corrected_error < 0.05 && raw_error > 5.0,
        "bias correction prevents synthetic six-axis yaw drift");
    FusionBiasInitialise(&bias);
    require(length(FusionBiasGetOffset(&bias)) == 0.0, "bias initialise clears offset");
    FusionBiasSetOffset(&bias, offset);
    require(length(FusionBiasUpdate(&bias, measured)) < 0.001,
        "saved calibration restores correction");
}

static void
reset_case(void)
{
    FusionAhrs used, fresh;
    FusionAhrsFlags flags;
    FusionVector acc, mag;
    int sample;
    initialise(&used);
    FusionAhrsSkipStartup(&used);
    for (sample = 0; sample < 100; sample++)
        FusionAhrsUpdateNoMagnetometer(&used, vector(0, 0, 90), vector(0, 0, 1));
    require(angle_error(checked_quaternion(&used), orientation(0, 0, 0)) > 80.0,
        "reset fixture starts from a rotated state");
    FusionAhrsRestart(&used);
    require(angle_error(checked_quaternion(&used), orientation(0, 0, 0)) < 0.001,
        "restart restores identity");
    flags = FusionAhrsGetFlags(&used);
    require(flags.startup && !flags.overrangeRecovery && !flags.accelerationRecovery &&
        !flags.magneticRecovery, "restart resets recovery flags and enables startup");
    initialise(&fresh);
    sensors(20, -10, 35, &acc, &mag);
    for (sample = 0; sample < 1000; sample++) {
        FusionAhrsUpdate(&used, vector(0, 0, 0), acc, mag);
        FusionAhrsUpdate(&fresh, vector(0, 0, 0), acc, mag);
        require(angle_error(checked_quaternion(&used), checked_quaternion(&fresh)) < 0.001,
            "restarted filter follows fresh-state trajectory");
    }
    require(angle_error(checked_quaternion(&used), orientation(20, -10, 35)) < 0.25,
        "restarted filter converges to the new orientation");
    puts("restart identity, flags, fresh-state replay and convergence pass");
}

int
main(int argc, char **argv)
{
    require(argc == 2, "one case name required");
    if (strcmp(argv[1], "static") == 0)
        static_case();
    else if (strcmp(argv[1], "rotation") == 0)
        rotation_case();
    else if (strcmp(argv[1], "bias") == 0)
        bias_case();
    else if (strcmp(argv[1], "reset") == 0)
        reset_case();
    else
        require(0, "unknown case");
    printf("PASS %s max_quaternion_norm_error=%.9g\n", argv[1], max_norm_error);
    return EXIT_SUCCESS;
}
