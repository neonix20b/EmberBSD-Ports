// SPDX-License-Identifier: MIT
#include <pcl/filters/passthrough.h>
#include <pcl/filters/voxel_grid.h>
#include <pcl/registration/icp.h>
#include "matrix-check.h"

#include <algorithm>
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>

using Point = pcl::PointXYZ;
using Cloud = pcl::PointCloud<Point>;

static void require(bool value, const char* message)
{
    if (!value) throw std::runtime_error(message);
}

static void filtering(bool empty)
{
    auto input = pcl::make_shared<Cloud>();
    if (!empty) {
        // Two occupied one-metre voxels, a distant point, and invalid input.
        input->push_back(Point(0.1f, 0.1f, 0.1f));
        input->push_back(Point(0.3f, 0.3f, 0.3f));
        input->push_back(Point(1.1f, 0.1f, 0.1f));
        input->push_back(Point(1.3f, 0.3f, 0.3f));
        input->push_back(Point(0.0f, 0.0f, 20.0f));
        input->push_back(Point(std::numeric_limits<float>::quiet_NaN(), 0, 0));
        input->is_dense = false;
    }
    pcl::PassThrough<Point> pass;
    pass.setInputCloud(input);
    pass.setFilterFieldName("z");
    pass.setFilterLimits(0.0f, 2.0f);
    auto bounded = pcl::make_shared<Cloud>();
    pass.filter(*bounded);
    require(bounded->size() == (empty ? 0u : 4u), "pass-through count");
    pcl::VoxelGrid<Point> voxel;
    voxel.setInputCloud(bounded);
    voxel.setLeafSize(1, 1, 1);
    Cloud result;
    voxel.filter(result);
    require(result.size() == (empty ? 0u : 2u), "voxel count");
    if (empty) return;
    std::sort(result.begin(), result.end(), [](const Point& a, const Point& b) {
        return a.x < b.x;
    });
    for (std::size_t i = 0; i < result.size(); ++i) {
        require(std::abs(result[i].x - (0.2f + i)) < 1e-6f, "voxel x centroid");
        require(std::abs(result[i].y - 0.2f) < 1e-6f, "voxel y centroid");
        require(std::abs(result[i].z - 0.2f) < 1e-6f, "voxel z centroid");
    }
}

static void registration(bool no_correspondence)
{
    auto source = pcl::make_shared<Cloud>();
    auto target = pcl::make_shared<Cloud>();
    constexpr float angle = 0.012f;
    const float cosine = std::cos(angle), sine = std::sin(angle);
    const float tx = no_correspondence ? 100.0f : 0.04f;
    // Fixed, asymmetric 3-D lattice with known point-to-point motion.
    for (int i = 0; i < 30; ++i) {
        const float x = (i % 5) * 0.8f + (i % 3) * 0.03f;
        const float y = ((i / 5) % 3) * 0.9f + (i % 2) * 0.07f;
        const float z = (i / 15) * 1.1f + (i % 7) * 0.04f;
        source->push_back(Point(x, y, z));
        // Construct the oracle directly, without PCL's transform operation.
        target->push_back(Point(cosine * x - sine * y + tx,
            sine * x + cosine * y - 0.03f, z + 0.02f));
    }
    pcl::IterativeClosestPoint<Point, Point> icp;
    icp.setInputSource(source);
    icp.setInputTarget(target);
    icp.setMaxCorrespondenceDistance(0.2);
    icp.setMaximumIterations(80);
    icp.setTransformationEpsilon(1e-12);
    icp.setEuclideanFitnessEpsilon(1e-12);
    Cloud aligned;
    icp.align(aligned);
    if (no_correspondence) {
        require(!icp.hasConverged(), "unmatched clouds reported convergence");
        return;
    }
    require(icp.hasConverged(), "ICP did not converge");
    Eigen::Matrix4f expected = Eigen::Matrix4f::Identity();
    expected(0, 0) = cosine;
    expected(0, 1) = -sine;
    expected(1, 0) = sine;
    expected(1, 1) = cosine;
    expected(0, 3) = tx;
    expected(1, 3) = -0.03f;
    expected(2, 3) = 0.02f;
    const Eigen::Matrix4f transform = icp.getFinalTransformation();
    require(finite_matrix_near(transform, expected, 1e-4f),
        "ICP transform differs from known rigid motion");
    const double fitness = icp.getFitnessScore();
    require(std::isfinite(fitness) && fitness >= 0 && fitness < 1e-8, "ICP final fitness");
    require(aligned.size() == target->size(), "ICP output count");
    for (std::size_t i = 0; i < aligned.size(); ++i)
        require((aligned[i].getVector3fMap() - (*target)[i].getVector3fMap()).norm() < 1e-4f,
            "ICP transformed point");
}

int main(int argc, char** argv)
{
    try {
        require(EIGEN_MAJOR_VERSION == 5 && EIGEN_MINOR_VERSION == 0 &&
            EIGEN_PATCH_VERSION == 1, "wrong Eigen headers");
        require(argc == 2, "expected one case");
        const std::string test = argv[1];
        if (test == "filter") filtering(false);
        else if (test == "empty-filter") filtering(true);
        else if (test == "registration") registration(false);
        else if (test == "no-correspondence") registration(true);
        else throw std::runtime_error("unknown case");
        std::cout << "PASS " << test << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << error.what() << '\n';
        return 1;
    }
}
