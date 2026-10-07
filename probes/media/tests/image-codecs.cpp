// SPDX-License-Identifier: MIT
#include <opencv2/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <vector>
static void require(bool ok, const char *message)
{
    if (!ok) throw std::runtime_error(message);
}
int main()
{
    try {
        require(cv::getVersionString() == "5.0.0", "OpenCV runtime version");
        cv::Mat depth(31, 47, CV_16UC1), rgb(32, 48, CV_8UC3);
        for (int y = 0; y < depth.rows; ++y)
            for (int x = 0; x < depth.cols; ++x)
                depth.at<unsigned short>(y, x) = 700 + y * 100 + x;
        for (int y = 0; y < rgb.rows; ++y)
            for (int x = 0; x < rgb.cols; ++x)
                rgb.at<cv::Vec3b>(y, x) = cv::Vec3b(40 + x, 80 + y, 140 + x / 2);
        std::vector<unsigned char> bytes;
        require(cv::imencode(".png", depth, bytes), "encode depth PNG");
        cv::Mat restored = cv::imdecode(bytes, cv::IMREAD_UNCHANGED);
        require(restored.type() == CV_16UC1 && restored.size() == depth.size(), "depth format");
        require(cv::norm(restored, depth, cv::NORM_INF) == 0, "lossless millimetre depth");
        require(cv::imencode(".jpg", rgb, bytes, {cv::IMWRITE_JPEG_QUALITY, 95}), "encode RGB JPEG");
        restored = cv::imdecode(bytes, cv::IMREAD_COLOR);
        require(restored.type() == CV_8UC3 && restored.size() == rgb.size(), "RGB format");
        require(cv::norm(restored, rgb, cv::NORM_L1) / (rgb.total() * 3) < 3.0, "bounded JPEG pixel error");
        bytes.assign(64, 0x5a);
        require(cv::imdecode(bytes, cv::IMREAD_UNCHANGED).empty(), "malformed image rejection");
        std::cout << "PASS PNG exact depth, JPEG bounded RGB, malformed bytes\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
