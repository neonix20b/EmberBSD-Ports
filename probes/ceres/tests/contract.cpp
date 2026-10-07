// SPDX-License-Identifier: MIT
#include <ceres/ceres.h>
#include <ceres/version.h>

#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>

static void require(bool condition, const char* message)
{
    if (!condition) throw std::runtime_error(message);
}

// Fit a non-linear exponential sensor response with two coupled parameters.
struct Response {
    double x, y;
    template <typename T>
    bool operator()(const T* const parameters, T* residual) const
    {
        residual[0] = ceres::exp(parameters[0] * T(x) + parameters[1]) - T(y);
        return true;
    }
};

struct UnavailableMeasurement {
    template <typename T>
    bool operator()(const T*, T*) const { return false; }
};

static ceres::Solver::Options options()
{
    ceres::Solver::Options result;
    result.linear_solver_type = ceres::DENSE_QR;
    result.max_num_iterations = 100;
    result.max_solver_time_in_seconds = 5.0;
    result.function_tolerance = 1e-12;
    result.gradient_tolerance = 1e-12;
    result.parameter_tolerance = 1e-12;
    result.num_threads = 1;
    result.logging_type = ceres::SILENT;
    return result;
}

static void optimize()
{
    double parameters[] = {-0.4, 0.8};
    ceres::Problem problem;
    for (int i = 0; i < 31; ++i) {
        const double x = i / 10.0;
        const double y = std::exp(0.3 * x + 0.1);
        problem.AddResidualBlock(new ceres::AutoDiffCostFunction<Response, 1, 2>(
            new Response{x, y}), nullptr, parameters);
    }
    ceres::Solver::Summary summary;
    ceres::Solve(options(), &problem, &summary);
    require(summary.termination_type == ceres::CONVERGENCE, "solver did not converge");
    require(summary.IsSolutionUsable(), "solution is unusable");
    require(summary.num_successful_steps > 0, "no optimization steps ran");
    require(std::abs(parameters[0] - 0.3) < 1e-8, "wrong fitted slope");
    require(std::abs(parameters[1] - 0.1) < 1e-8, "wrong fitted intercept");
    require(summary.final_cost < 1e-16 && summary.initial_cost > 1.0,
        "cost did not decrease to the known minimum");
    double max_residual = 0.0;
    for (int i = 0; i < 31; ++i) {
        const double x = i / 10.0;
        max_residual = std::max(max_residual,
            std::abs(std::exp(parameters[0] * x + parameters[1]) - std::exp(0.3 * x + 0.1)));
    }
    require(max_residual < 1e-8, "fitted response residual too large");
    std::cout << "slope=" << parameters[0] << " intercept=" << parameters[1]
              << " max_residual=" << max_residual << " cost=" << summary.final_cost << '\n';
}

static void invalid_options()
{
    double parameters[] = {0.2, 0.2};
    ceres::Problem problem;
    problem.AddResidualBlock(new ceres::AutoDiffCostFunction<Response, 1, 2>(
        new Response{1.0, std::exp(0.4)}), nullptr, parameters);
    auto invalid = options();
    invalid.max_num_iterations = -1;
    std::string error;
    require(!invalid.IsValid(&error) && !error.empty(), "invalid options accepted");
    ceres::Solver::Summary summary;
    ceres::Solve(invalid, &problem, &summary);
    require(summary.termination_type == ceres::FAILURE && !summary.IsSolutionUsable(),
        "invalid options did not fail solving");
    require(parameters[0] == 0.2 && parameters[1] == 0.2, "invalid solve modified parameters");
}

static void invalid_residual()
{
    double parameter = 3.0;
    ceres::Problem problem;
    problem.AddResidualBlock(new ceres::AutoDiffCostFunction<UnavailableMeasurement, 1, 1>(
        new UnavailableMeasurement), nullptr, &parameter);
    ceres::Solver::Summary summary;
    ceres::Solve(options(), &problem, &summary);
    require(summary.termination_type == ceres::FAILURE && !summary.IsSolutionUsable(),
        "failed residual evaluation was accepted");
    require(!summary.message.empty() && parameter == 3.0,
        "failed residual evaluation lost diagnostics or modified state");
}

int main(int argc, char** argv)
{
    try {
        require(std::string(CERES_VERSION_STRING) == "2.2.0", "wrong Ceres headers");
        require(EIGEN_MAJOR_VERSION == 5 && EIGEN_MINOR_VERSION == 0 &&
            EIGEN_PATCH_VERSION == 1, "wrong Eigen headers");
        require(argc == 2, "one test case is required");
        const std::string test = argv[1];
        if (test == "optimize") optimize();
        else if (test == "invalid-options") invalid_options();
        else if (test == "invalid-residual") invalid_residual();
        else throw std::runtime_error("unknown test case");
        std::cout << "PASS Ceres " << test << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL Ceres: " << error.what() << '\n';
        return 1;
    }
}
