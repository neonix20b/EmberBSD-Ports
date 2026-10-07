// SPDX-License-Identifier: BSD-2-Clause
// Origin: EmberBSD; AI-assisted real KFileMetadata/FFmpeg boundary regression.
#include "ffmpegextractor.h"
#include "simpleextractionresult.h"
#include "qffmpegdefs_p.h"
#include <QCoreApplication>
#include <QDebug>

static_assert(LIBAVCODEC_VERSION_MAJOR == 63);
static_assert(LIBAVCODEC_VERSION_INT >= AV_VERSION_INT(63, 1, 102));
static_assert(LIBAVFORMAT_VERSION_MAJOR == 63);
static_assert(LIBAVUTIL_VERSION_MAJOR == 61);
static_assert(QT_FFMPEG_HAS_AVCODEC_GET_SUPPORTED_CONFIG);
static_assert(QT_FFMPEG_HAS_AV_CHANNEL_LAYOUT);
static_assert(QT_FFMPEG_HAS_SWS_FLAGS_ENUM);

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc != 3)
        return 2;
    using namespace KFileMetaData;
    FFmpegExtractor extractor;
    SimpleExtractionResult valid(QString::fromLocal8Bit(argv[1]),
                                 QStringLiteral("video/x-matroska"));
    extractor.extract(&valid);
    const auto properties = valid.properties();
    if (properties.value(Property::Width).toInt() != 64
        || properties.value(Property::Height).toInt() != 48
        || properties.value(Property::VideoCodec).toString() != QStringLiteral("ffv1")
        || properties.value(Property::Title).toString() != QStringLiteral("Ember FFmpeg 9")
        || !valid.types().contains(Type::Video)) {
        qCritical() << "Unexpected real extractor result:" << properties;
        return 1;
    }
    SimpleExtractionResult invalid(QString::fromLocal8Bit(argv[2]),
                                   QStringLiteral("video/x-matroska"));
    extractor.extract(&invalid);
    if (!invalid.properties().isEmpty() || !invalid.types().isEmpty())
        return 1;
    qInfo() << "PASS: Qt FFmpeg definitions compile; actual KFileMetadata extractor"
               " reads dimensions/codec/title and rejects invalid media";
    return 0;
}
