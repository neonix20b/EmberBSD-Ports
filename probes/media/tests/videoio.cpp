// SPDX-License-Identifier: MIT
#include <opencv2/core.hpp>
#include <opencv2/core/utils/filesystem.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/videoio.hpp>
#include <cmath>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include <unistd.h>
#include "pattern.h"

static void require(bool ok, const char *what)
{
    if (!ok) throw std::runtime_error(what);
}

static void check_frame(const cv::Mat &frame, int number, bool mask)
{
    require(frame.rows == HEIGHT && frame.cols == WIDTH && frame.type() == CV_8UC3,
            "decoded dimensions/type");
    for (int y = 0; y < HEIGHT; ++y) {
        for (int x = 0; x < WIDTH; ++x) {
            auto value = pixel(number, x, y);
            if (mask) value = value > 127 ? 255 : 0;
            require(frame.at<cv::Vec3b>(y, x) == cv::Vec3b(value, value, value),
                    "exact decoded pixels");
        }
    }
}

static void read_all(cv::VideoCapture &capture, bool mask, bool timestamp)
{
    cv::Mat frame;
    for (int i = 0; i < FRAMES; ++i) {
        require(capture.read(frame), "complete video frame count");
        check_frame(frame, i, mask);
        if (timestamp)
            require(std::abs(capture.get(cv::CAP_PROP_POS_MSEC) - i * 1000.0 / FPS) < 0.01,
                    "capture timestamp");
    }
    require(!capture.read(frame) && frame.empty(), "end of stream without stale frame");
}

int main(int argc, char **argv)
{
    alarm(60);
    try {
        require(argc == 3, "usage: videoio-contract INPUT_MKV WORK_DIRECTORY");
        require(cv::getVersionString() == "5.0.0", "OpenCV runtime version");
        cv::setNumThreads(1);
        const std::string source = argv[1], work = argv[2];
        // Paths enter a GStreamer pipeline only after the shell guard checks them.
        require(!work.empty() && work[0] == '/' &&
                work.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-") ==
                std::string::npos, "simple absolute work path required");
        std::cout << cv::getBuildInformation() << '\n';
        require(cv::utils::fs::exists(source) && !cv::utils::fs::exists(source + ".missing"),
                "filesystem existing/missing path");
        require(cv::utils::fs::isDirectory(work) && !cv::utils::fs::getcwd().empty(),
                "filesystem directory/current path");
        const std::string directory = work + "/filesystem-" + std::to_string(getpid());
        require(!cv::utils::fs::exists(directory) && cv::utils::fs::createDirectories(directory + "/child"),
                "filesystem recursive mkdir");
        std::ofstream marker(directory + "/child/marker");
        marker << "fixture\n";
        marker.close();
        require(marker.good(), "filesystem marker write");
        std::vector<cv::String> paths;
        cv::utils::fs::glob(directory, "marker", paths, true);
        require(paths.size() == 1 && paths[0] == directory + "/child/marker",
                "filesystem recursive glob");
        require(cv::utils::fs::exists(cv::utils::fs::canonical(paths[0])), "filesystem canonical path");
        cv::utils::fs::remove_all(directory);
        require(!cv::utils::fs::exists(directory), "filesystem owned-tree removal");
        cv::VideoCapture capture(source, cv::CAP_FFMPEG);
        require(capture.isOpened() && capture.getBackendName() == "FFMPEG", "explicit FFmpeg capture");
        require(std::abs(capture.get(cv::CAP_PROP_FPS) - FPS) < 1e-6, "capture frame rate");
        read_all(capture, false, true);
        require(capture.set(cv::CAP_PROP_POS_FRAMES, 5), "seek to frame 5");
        cv::Mat frame;
        require(capture.read(frame), "read after seek");
        check_frame(frame, 5, false);
        capture.release();

        capture.open(source, cv::CAP_FFMPEG);
        require(capture.isOpened(), "reopen source");
        const std::string processed = work + "/processed.mkv";
        cv::VideoWriter writer(processed, cv::CAP_FFMPEG,
                cv::VideoWriter::fourcc('F', 'F', 'V', '1'), FPS, cv::Size(WIDTH, HEIGHT), false);
        require(writer.isOpened() && writer.getBackendName() == "FFMPEG", "explicit FFV1 writer");
        for (int i = 0; i < FRAMES; ++i) {
            require(capture.read(frame), "read processing frame");
            cv::Mat gray, mask;
            cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
            cv::threshold(gray, mask, 127, 255, cv::THRESH_BINARY);
            writer.write(mask);
        }
        writer.release();
        capture.release();
        capture.open(processed, cv::CAP_FFMPEG);
        require(capture.isOpened(), "reopen processed video");
        read_all(capture, true, true);
        capture.release();

        const std::string raw = work + "/frames.gray";
        std::ofstream output(raw, std::ios::binary);
        for (int i = 0; i < FRAMES; ++i)
            for (int y = 0; y < HEIGHT; ++y)
                for (int x = 0; x < WIDTH; ++x)
                    output.put(static_cast<char>(pixel(i, x, y)));
        output.close();
        require(output.good(), "write raw video fixture");
        const std::string pipeline = "filesrc location=" + raw +
            " ! rawvideoparse format=gray8 width=64 height=48 framerate=25/1"
            " ! videoconvert ! video/x-raw,format=BGR ! appsink";
        capture.open(pipeline, cv::CAP_GSTREAMER);
        require(capture.isOpened() && capture.getBackendName() == "GSTREAMER",
                "explicit GStreamer file capture");
        read_all(capture, false, false); // GStreamer POS_MSEC is a pipeline query, not the sample PTS.
        capture.release();
        cv::VideoCapture missing(source + ".missing", cv::CAP_FFMPEG);
        require(!missing.isOpened(), "missing input rejected");
        std::ofstream invalid(work + "/invalid.video");
        invalid << "not a video\n";
        invalid.close();
        cv::VideoCapture malformed(work + "/invalid.video", cv::CAP_FFMPEG);
        require(!malformed.isOpened(), "malformed input rejected");
        std::cout << "PASS OpenCV videoio: POSIX filesystem, FFmpeg file/seek/threshold/write/read, "
                     "GStreamer raw file, exact pixels/count/EOF, invalid input\n";
    } catch (const std::exception &e) {
        std::cerr << "FAIL OpenCV videoio: " << e.what() << '\n';
        return 1;
    }
}
