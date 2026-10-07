/* SPDX-License-Identifier: MIT */
/* Copyright (c) 2026 EmberBSD contributors */
#include <osqp.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if !defined(OSQP_ENABLE_INTERRUPT) || !defined(OSQP_ENABLE_PROFILING)
#error "The full signal listener and timing support are required"
#endif
_Static_assert(sizeof(OSQPFloat) == 8, "Double precision required");
_Static_assert(sizeof(OSQPInt) == 8, "64-bit indices required");

static void
require(int condition, const char *message)
{

	if (!condition) {
		fprintf(stderr, "FAIL: %s\n", message);
		exit(1);
	}
}

static void
settings_init(OSQPSettings *settings)
{

	osqp_set_default_settings(settings);
	settings->verbose = 0;
	settings->polishing = 1;
	settings->eps_abs = settings->eps_rel = 1e-8;
	settings->max_iter = 10000;
	settings->time_limit = 5.0;
}

static void
check_solution(OSQPSolver *solver, double diagonal, const OSQPFloat *q,
    const OSQPFloat *lower, const OSQPFloat *upper, double x0, double x1,
    double objective)
{
	const double tolerance = 2e-6;
	OSQPFloat *x = solver->solution->x, *y = solver->solution->y;
	double values[3] = { x[0] + x[1], x[0], x[1] };
	double computed;
	int i;

	require(solver->info->status_val == OSQP_SOLVED, "QP not solved accurately");
	require(fabs(x[0] - x0) < tolerance && fabs(x[1] - x1) < tolerance,
	    "Primal result differs from analytic optimum");
	for (i = 0; i < 3; i++) {
		require(isfinite(values[i]) && isfinite(y[i]), "Non-finite result");
		require(values[i] >= lower[i] - tolerance &&
		    values[i] <= upper[i] + tolerance, "Primal bound violation");
		require(fabs(y[i] * (values[i] -
		    (y[i] >= 0 ? upper[i] : lower[i]))) < tolerance,
		    "Complementarity failed");
	}
	require(fabs(diagonal * x[0] + q[0] + y[0] + y[1]) < tolerance &&
	    fabs(diagonal * x[1] + q[1] + y[0] + y[2]) < tolerance,
	    "Independent KKT stationarity failed");
	require(fabs(y[0] - 1) < tolerance, "Active sum dual differs from one");
	computed = 0.5 * diagonal * (x[0] * x[0] + x[1] * x[1]) +
	    q[0] * x[0] + q[1] * x[1];
	require(fabs(computed - objective) < tolerance &&
	    fabs(solver->info->obj_val - objective) < tolerance,
	    "Objective differs from independent calculation");
	require(solver->info->prim_res < tolerance &&
	    solver->info->dual_res < tolerance, "Solver residuals too large");
	require(isfinite(solver->info->run_time) && solver->info->run_time > 0 &&
	    solver->info->setup_time > 0, "Enabled timing did not record work");
}

static void
quadratic_program(void)
{
	OSQPFloat px[2] = { 2, 2 }, ax[4] = { 1, 1, 1, 1 };
	OSQPInt pi[2] = { 0, 1 }, pp[3] = { 0, 1, 2 };
	OSQPInt ai[4] = { 0, 1, 0, 2 }, ap[3] = { 0, 2, 4 };
	OSQPFloat q[2] = { -2, -4 }, lower[3] = { -10, 0, 0 };
	OSQPFloat upper[3] = { 2, 10, 10 }, warm[2] = { .5, 1.5 };
	OSQPCscMatrix *p = OSQPCscMatrix_new(2, 2, 2, px, pi, pp);
	OSQPCscMatrix *a = OSQPCscMatrix_new(3, 2, 4, ax, ai, ap);
	OSQPSettings settings;
	OSQPSolver *solver = NULL;

	settings_init(&settings);
	require(p && a, "Matrix allocation failed");
	require(osqp_setup(&solver, p, q, a, lower, upper, 3, 2, &settings) == 0,
	    "QP setup failed");
	require(osqp_solve(solver) == 0, "QP solve failed");
	check_solution(solver, 2, q, lower, upper, .5, 1.5, -4.5);
	q[0] = -4;
	q[1] = -2;
	require(osqp_update_data_vec(solver, q, NULL, NULL) == 0,
	    "Linear cost update failed");
	require(osqp_warm_start(solver, warm, NULL) == 0, "Warm start failed");
	require(osqp_solve(solver) == 0, "Updated QP solve failed");
	check_solution(solver, 2, q, lower, upper, 1.5, .5, -4.5);
	px[0] = px[1] = 4;
	upper[0] = 1;
	require(osqp_update_data_mat(solver, px, NULL, 2, NULL, NULL, 0) == 0,
	    "Hessian update failed");
	require(osqp_update_data_vec(solver, NULL, NULL, upper) == 0,
	    "Bound update failed");
	require(osqp_solve(solver) == 0, "Matrix/bound update solve failed");
	check_solution(solver, 4, q, lower, upper, .75, .25, -2.25);
	osqp_cleanup(solver);
	OSQPCscMatrix_free(a);
	OSQPCscMatrix_free(p);
	puts("QP analytic optima, KKT, finite bounds, timing, updates and warm start: PASS");
}

static void
infeasible(void)
{
	OSQPFloat px[1] = { 2 }, ax[2] = { 1, 1 }, q[1] = { 0 };
	OSQPInt pi[1] = { 0 }, pp[2] = { 0, 1 };
	OSQPInt ai[2] = { 0, 1 }, ap[2] = { 0, 2 };
	OSQPFloat lower[2] = { 1, -2 }, upper[2] = { 2, 0 };
	OSQPCscMatrix *p = OSQPCscMatrix_new(1, 1, 1, px, pi, pp);
	OSQPCscMatrix *a = OSQPCscMatrix_new(2, 1, 2, ax, ai, ap);
	OSQPSettings settings;
	OSQPSolver *solver = NULL;
	OSQPFloat *certificate;
	double separation = 0;
	int i;

	settings_init(&settings);
	require(p && a, "Matrix allocation failed");
	require(osqp_setup(&solver, p, q, a, lower, upper, 2, 1, &settings) == 0,
	    "Valid but infeasible problem was rejected during setup");
	require(osqp_solve(solver) == 0, "Infeasible solve API failed");
	require(solver->info->status_val == OSQP_PRIMAL_INFEASIBLE,
	    "Contradictory constraints were not detected");
	certificate = solver->solution->prim_inf_cert;
	require(certificate != NULL, "Missing primal infeasibility certificate");
	for (i = 0; i < 2; i++) {
		require(isfinite(certificate[i]), "Non-finite certificate");
		separation += certificate[i] *
		    (certificate[i] > 0 ? upper[i] : lower[i]);
	}
	require(fabs(certificate[0] + certificate[1]) < 1e-5 && separation < -0.5,
	    "Certificate fails independent A-transpose-v and separation checks");
	osqp_cleanup(solver);
	OSQPCscMatrix_free(a);
	OSQPCscMatrix_free(p);
	puts("Infeasible status and independently checked certificate: PASS");
}

int
main(int argc, char **argv)
{

	require(argc == 2 && strcmp(osqp_version(), "1.0.0") == 0,
	    "Unexpected arguments or OSQP version");
	require(osqp_capabilities() & OSQP_CAPABILITY_DIRECT_SOLVER,
	    "Missing direct QDLDL backend");
	if (strcmp(argv[1], "qp") == 0)
		quadratic_program();
	else if (strcmp(argv[1], "infeasible") == 0)
		infeasible();
	else
		require(0, "Unknown test mode");
	return 0;
}
