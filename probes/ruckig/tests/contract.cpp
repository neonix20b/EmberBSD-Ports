// SPDX-License-Identifier: MIT
// Copyright (c) 2026 EmberBSD contributors
// Original analytic and synthetic fixtures, developed with AI assistance.
#include <ruckig/ruckig.hpp>
#include <array>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

#ifdef WITH_CLOUD_CLIENT
#error "The autonomous profile must not enable the cloud client"
#endif

namespace {
void require(bool condition, const char* message)
{
    if (!condition) throw std::runtime_error(message);
}
void near(double actual, double expected, double tolerance, const char* message)
{
    require(std::isfinite(actual) && std::abs(actual - expected) <= tolerance, message);
}

void analytic()
{
    ruckig::Ruckig<1> generator;
    ruckig::InputParameter<1> input;
    input.current_position = {0};
    input.current_velocity = {0};
    input.current_acceleration = {0};
    input.target_position = {1};
    input.target_velocity = {0};
    input.target_acceleration = {0};
    input.max_velocity = {10};
    input.max_acceleration = {10};
    input.max_jerk = {2};
    ruckig::Trajectory<1> trajectory;
    require(generator.calculate(input, trajectory) == ruckig::Result::Working,
            "analytic motion calculation failed");
    // Rest-to-rest displacement D with only jerk J active has four equal
    // phases: +J, -J, -J, +J; D = 2*J*tj^3 and duration = 4*tj.
    const double tj = std::cbrt(1.0 / 4.0);
    near(trajectory.get_duration(), 4 * tj, 1e-9, "wrong analytic duration");
    std::array<double, 1> p, v, a;
    trajectory.at_time(2 * tj, p, v, a);
    near(p[0], 0.5, 1e-10, "wrong midpoint position");
    near(v[0], 2 * tj * tj, 1e-10, "wrong midpoint velocity");
    near(a[0], 0, 1e-10, "wrong midpoint acceleration");
    double last_a = 0;
    const double dt = trajectory.get_duration() / 1000;
    for (unsigned i = 0; i <= 1000; ++i) {
        trajectory.at_time(i * dt, p, v, a);
        require(std::isfinite(p[0]) && std::isfinite(v[0]) && std::isfinite(a[0]),
                "nonfinite trajectory");
        require(p[0] >= -1e-9 && p[0] <= 1 + 1e-9, "position overshoot");
        require(std::abs(v[0]) <= 10 && std::abs(a[0]) <= 10, "bound exceeded");
        if (i) require(std::abs(a[0] - last_a) <= 2 * dt + 1e-10,
                       "finite-difference jerk exceeds bound");
        last_a = a[0];
    }
    near(p[0], 1, 1e-9, "wrong endpoint position");
    near(v[0], 0, 1e-9, "wrong endpoint velocity");
    near(a[0], 0, 1e-9, "wrong endpoint acceleration");
    std::cout << "analytic_samples=1001 duration=" << trajectory.get_duration() << '\n';
}

using Trace = std::vector<std::array<double, 12>>;

Trace online_once()
{
    constexpr double dt = 0.01;
    ruckig::Ruckig<3> generator(dt);
    ruckig::InputParameter<3> input;
    ruckig::OutputParameter<3> output;
    input.current_position = {0, 0, 0};
    input.current_velocity = {0, 0, 0};
    input.current_acceleration = {0, 0, 0};
    input.target_position = {1, -2, 0.3};
    input.target_velocity = {0, 0, 0};
    input.target_acceleration = {0, 0, 0};
    input.max_velocity = {1, 1.2, 0.8};
    input.max_acceleration = {1, 1.5, 0.8};
    input.max_jerk = {2, 3, 1};
    std::array<double, 3> previous_a = input.current_acceleration;
    Trace trace;
    unsigned replans = 0;
    for (unsigned step = 0; step < 5000; ++step) {
        if (step == 50) input.target_position[0] = 1.3;
        const auto result = generator.update(input, output);
        require(result == ruckig::Result::Working || result == ruckig::Result::Finished,
                "online motion calculation failed");
        replans += output.new_calculation;
        for (unsigned axis = 0; axis < 3; ++axis) {
            require(std::isfinite(output.new_position[axis]) &&
                    std::isfinite(output.new_velocity[axis]) &&
                    std::isfinite(output.new_acceleration[axis]) &&
                    std::isfinite(output.new_jerk[axis]), "nonfinite online state");
            require(std::abs(output.new_velocity[axis]) <= input.max_velocity[axis] + 1e-8,
                    "online velocity bound");
            require(std::abs(output.new_acceleration[axis]) <= input.max_acceleration[axis] + 1e-8,
                    "online acceleration bound");
            require(std::abs(output.new_jerk[axis]) <= input.max_jerk[axis] + 1e-8,
                    "online jerk bound");
            require(std::abs(output.new_acceleration[axis] - previous_a[axis]) <=
                    dt * input.max_jerk[axis] + 1e-8, "online jerk continuity");
        }
        previous_a = output.new_acceleration;
        std::array<double, 12> state;
        for (unsigned axis = 0; axis < 3; ++axis) {
            state[axis] = output.new_position[axis];
            state[3 + axis] = output.new_velocity[axis];
            state[6 + axis] = output.new_acceleration[axis];
            state[9 + axis] = output.new_jerk[axis];
        }
        trace.push_back(state);
        if (result == ruckig::Result::Finished) {
            require(step > 50 && replans == 2, "target change did not replan exactly once");
            for (unsigned axis = 0; axis < 3; ++axis) {
                near(output.new_position[axis], input.target_position[axis], 1e-8, "online endpoint");
                near(output.new_velocity[axis], 0, 1e-8, "online final velocity");
                near(output.new_acceleration[axis], 0, 1e-8, "online final acceleration");
            }
            return trace;
        }
        output.pass_to_input(input);
    }
    throw std::runtime_error("online motion did not finish within 50 simulated seconds");
}

void invalid()
{
    ruckig::Ruckig<1> generator;
    ruckig::InputParameter<1> valid;
    valid.current_position = {0}; valid.current_velocity = {0}; valid.current_acceleration = {0};
    valid.target_position = {1}; valid.target_velocity = {0}; valid.target_acceleration = {0};
    valid.max_velocity = {1}; valid.max_acceleration = {1}; valid.max_jerk = {2};
    for (unsigned which = 0; which < 5; ++which) {
        auto input = valid;
        if (which == 0) input.max_jerk[0] = -1;
        if (which == 1) input.max_acceleration[0] = -1;
        if (which == 2) input.current_position[0] = std::numeric_limits<double>::quiet_NaN();
        if (which == 3) input.target_velocity[0] = 2;
        if (which == 4) input.intermediate_positions.push_back({0.5});
        ruckig::Trajectory<1> trajectory;
        require(generator.calculate(input, trajectory) == ruckig::Result::ErrorInvalidInput,
                "invalid input or unsupported cloud waypoint accepted");
    }
    std::cout << "invalid_inputs_rejected=5 cloud_client=disabled\n";
}
}

int main(int argc, char** argv)
{
    try {
        require(argc == 2, "choose analytic, online or invalid");
        const std::string mode = argv[1];
        if (mode == "analytic") analytic();
        else if (mode == "online") {
            const auto trace = online_once();
            require(online_once() == trace, "fresh generator changed the complete motion trace");
            std::cout << "online_axes=3 steps=" << trace.size()
                      << " restarts=1 target_replans=1 trace_values=" << trace.size() * 12 << '\n';
        } else if (mode == "invalid") invalid();
        else throw std::runtime_error("unknown case");
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << "FAIL: " << error.what() << '\n';
        return EXIT_FAILURE;
    }
}
