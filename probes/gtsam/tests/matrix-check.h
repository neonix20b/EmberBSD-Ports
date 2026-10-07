// SPDX-License-Identifier: MIT
#ifndef EMBER_MATRIX_CHECK_H
#define EMBER_MATRIX_CHECK_H
#include <Eigen/Core>
#include <cmath>
template<class Actual, class Expected>
bool finite_matrix_near(const Eigen::MatrixBase<Actual>& actual,
                        const Eigen::MatrixBase<Expected>& expected,
                        typename Actual::Scalar tolerance)
{
    return actual.allFinite() && expected.allFinite() &&
        std::isfinite(tolerance) && tolerance > 0 &&
        (actual - expected).cwiseAbs().maxCoeff() < tolerance;
}
#endif
