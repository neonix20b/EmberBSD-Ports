// SPDX-License-Identifier: MIT
#include <Eigen/Dense>
#include <Eigen/Geometry>
#include <Eigen/Sparse>
#include <Eigen/Version>
#include <cmath>
#include <iostream>
#include <stdexcept>

static void require(bool ok, const char *what)
{
    if (!ok) throw std::runtime_error(what);
}

int main()
{
    try {
        static_assert(EIGEN_MAJOR_VERSION == 5 && EIGEN_MINOR_VERSION == 0 &&
                      EIGEN_PATCH_VERSION == 1, "Expected Eigen 5.0.1");
        Eigen::Matrix3d a;
        a << 4, 1, 0, 1, 3, 1, 0, 1, 2;
        const Eigen::Vector3d b(1, 2, 3);
        const Eigen::Vector3d x = a.ldlt().solve(b);
        require(x.allFinite() && (a * x - b).norm() < 1e-12, "dense residual");
        Eigen::JacobiSVD<Eigen::Matrix3d> svd(a, Eigen::ComputeFullU | Eigen::ComputeFullV);
        require((svd.matrixU() * svd.singularValues().asDiagonal() *
                 svd.matrixV().transpose() - a).norm() < 1e-12, "SVD reconstruction");
        Eigen::Matrix3d singular = a;
        singular.row(2) = singular.row(1);
        require(singular.fullPivLu().rank() == 2, "rank-deficient detection");
        Eigen::SparseMatrix<double> sparse = a.sparseView();
        Eigen::SimplicialLDLT<Eigen::SparseMatrix<double>> solver(sparse);
        require(solver.info() == Eigen::Success, "sparse factorization");
        Eigen::Vector3d sx = solver.solve(b);
        require(solver.info() == Eigen::Success && sx.allFinite() &&
                (sparse * sx - b).norm() < 1e-12, "sparse residual");
        Eigen::Isometry3d pose = Eigen::Isometry3d::Identity();
        pose.rotate(Eigen::AngleAxisd(std::acos(-1.0) / 2, Eigen::Vector3d::UnitZ()));
        pose.translation() = Eigen::Vector3d(1, 2, 3);
        require((pose * Eigen::Vector3d(1, 0, 0) - Eigen::Vector3d(1, 3, 3)).norm()
                < 1e-12, "rigid transform");
        require((pose.inverse() * (pose * b) - b).norm() < 1e-12, "inverse transform");
        std::cout << "PASS Eigen 5.0.1: dense, sparse, SVD, rank and transforms\n";
    } catch (const std::exception &e) {
        std::cerr << "FAIL Eigen: " << e.what() << '\n';
        return 1;
    }
}
