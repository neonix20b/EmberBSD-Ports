// SPDX-License-Identifier: MIT
#include "matrix-check.h"
#include <iostream>
#include <limits>
#include <stdexcept>
template<class Matrix>
void check()
{
    using Scalar = typename Matrix::Scalar;
    const Matrix expected = Matrix::Identity();
    const Scalar tolerance = Scalar(1e-4);
    if (!finite_matrix_near(expected, expected, tolerance))
        throw std::runtime_error("exact finite matrix rejected");
    Matrix actual = expected;
    actual(0, 0) += Scalar(1);
    if (finite_matrix_near(actual, expected, tolerance))
        throw std::runtime_error("finite incorrect matrix accepted");
    for (int row = 0; row < actual.rows(); ++row)
        for (int col = 0; col < actual.cols(); ++col)
            for (Scalar invalid : {std::numeric_limits<Scalar>::quiet_NaN(),
                                   std::numeric_limits<Scalar>::infinity(),
                                   -std::numeric_limits<Scalar>::infinity()}) {
                actual = expected;
                actual(row, col) = invalid;
                if (finite_matrix_near(actual, expected, tolerance))
                    throw std::runtime_error("nonfinite coefficient accepted");
            }
}
int main()
{
    try {
        check<Eigen::Matrix3d>();
        check<Eigen::Matrix4f>();
        std::cout << "PASS finite matrix oracle: NaN/Inf in all 25 coefficients\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
