/* SPDX-License-Identifier: MIT */
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include "pattern.h"

static atomic_int decode_diagnostic;

static void
strict_log(void *context, int level, const char *format, va_list args)
{
	if (level <= AV_LOG_WARNING)
		atomic_store(&decode_diagnostic, 1);
	av_log_default_callback(context, level, format, args);
}

static void
require(int ok, const char *what)
{
	if (!ok) {
		fprintf(stderr, "FAIL FFmpeg: %s\n", what);
		exit(1);
	}
}

static void
check(int result, const char *what)
{
	char error[AV_ERROR_MAX_STRING_SIZE];

	if (result < 0) {
		av_strerror(result, error, sizeof(error));
		fprintf(stderr, "FAIL FFmpeg: %s: %s\n", what, error);
		exit(1);
	}
}

static void
write_packets(AVCodecContext *encoder, AVFormatContext *mux,
    AVStream *stream, AVPacket *packet, int draining)
{
	int result;

	while ((result = avcodec_receive_packet(encoder, packet)) >= 0) {
		av_packet_rescale_ts(packet, encoder->time_base, stream->time_base);
		packet->stream_index = stream->index;
		check(av_interleaved_write_frame(mux, packet), "write packet");
		av_packet_unref(packet);
	}
	require(result == (draining ? AVERROR_EOF : AVERROR(EAGAIN)),
	    "encoder drain state");
}

static void
encode(const char *path)
{
	AVFormatContext *mux = NULL;
	const AVCodec *codec = avcodec_find_encoder(AV_CODEC_ID_FFV1);
	AVCodecContext *encoder;
	AVStream *stream;
	AVFrame *frame;
	AVPacket *packet;
	int i, x, y;

	require(codec != NULL, "FFV1 encoder available");
	check(avformat_alloc_output_context2(&mux, NULL, "matroska", path),
	    "allocate Matroska muxer");
	encoder = avcodec_alloc_context3(codec);
	stream = avformat_new_stream(mux, NULL);
	frame = av_frame_alloc();
	packet = av_packet_alloc();
	require(encoder && stream && frame && packet, "allocate encoder objects");
	encoder->width = WIDTH;
	encoder->height = HEIGHT;
	encoder->pix_fmt = AV_PIX_FMT_GRAY8;
	encoder->time_base = (AVRational){1, FPS};
	encoder->framerate = (AVRational){FPS, 1};
	encoder->thread_count = 1;
	encoder->flags |= AV_CODEC_FLAG_BITEXACT;
	if (mux->oformat->flags & AVFMT_GLOBALHEADER)
		encoder->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
	check(avcodec_open2(encoder, codec, NULL), "open FFV1 encoder");
	check(avcodec_parameters_from_context(stream->codecpar, encoder),
	    "copy encoder parameters");
	stream->time_base = encoder->time_base;
	stream->avg_frame_rate = encoder->framerate;
	mux->flags |= AVFMT_FLAG_BITEXACT;
	check(avio_open(&mux->pb, path, AVIO_FLAG_WRITE), "open output file");
	check(avformat_write_header(mux, NULL), "write container header");
	frame->format = encoder->pix_fmt;
	frame->width = WIDTH;
	frame->height = HEIGHT;
	check(av_frame_get_buffer(frame, 32), "allocate pixels");
	for (i = 0; i < FRAMES; i++) {
		check(av_frame_make_writable(frame), "writable pixels");
		for (y = 0; y < HEIGHT; y++)
			for (x = 0; x < WIDTH; x++)
				frame->data[0][y * frame->linesize[0] + x] = pixel(i, x, y);
		frame->pts = i;
		frame->duration = 1;
		check(avcodec_send_frame(encoder, frame), "send frame");
		write_packets(encoder, mux, stream, packet, 0);
	}
	check(avcodec_send_frame(encoder, NULL), "flush encoder");
	write_packets(encoder, mux, stream, packet, 1);
	check(av_write_trailer(mux), "write container trailer");
	check(avio_closep(&mux->pb), "close output file");
	av_packet_free(&packet);
	av_frame_free(&frame);
	avcodec_free_context(&encoder);
	avformat_free_context(mux);
}

static void
read_frames(AVCodecContext *decoder, AVStream *stream, AVFrame *frame,
    int *count, int draining)
{
	int result, x, y;
	int64_t expected;

	while ((result = avcodec_receive_frame(decoder, frame)) >= 0) {
		require(*count < FRAMES, "no extra frame");
		require(frame->width == WIDTH && frame->height == HEIGHT &&
		    frame->format == AV_PIX_FMT_GRAY8, "decoded dimensions and format");
		expected = av_rescale_q(*count, (AVRational){1, FPS}, stream->time_base);
		require(frame->best_effort_timestamp == expected, "decoded timestamp");
		for (y = 0; y < HEIGHT; y++)
			for (x = 0; x < WIDTH; x++)
				require(frame->data[0][y * frame->linesize[0] + x] ==
				    pixel(*count, x, y), "lossless pixel round trip");
		(*count)++;
		av_frame_unref(frame);
	}
	require(result == (draining ? AVERROR_EOF : AVERROR(EAGAIN)),
	    "decoder drain state");
}

static void
decode(const char *path)
{
	AVFormatContext *demux = NULL;
	AVCodecContext *decoder;
	const AVCodec *codec;
	AVStream *stream;
	AVFrame *frame;
	AVPacket *packet;
	int index, result, count = 0;

	atomic_store(&decode_diagnostic, 0);
	av_log_set_callback(strict_log);
	check(avformat_open_input(&demux, path, NULL, NULL), "open input");
	check(avformat_find_stream_info(demux, NULL), "find stream metadata");
	index = av_find_best_stream(demux, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
	check(index, "find video stream");
	stream = demux->streams[index];
	require(stream->codecpar->codec_id == AV_CODEC_ID_FFV1, "FFV1 stream");
	decoder = avcodec_alloc_context3(codec);
	frame = av_frame_alloc();
	packet = av_packet_alloc();
	require(decoder && frame && packet, "allocate decoder objects");
	check(avcodec_parameters_to_context(decoder, stream->codecpar), "copy metadata");
	decoder->thread_count = 1;
	decoder->err_recognition = AV_EF_EXPLODE;
	check(avcodec_open2(decoder, codec, NULL), "open decoder");
	while ((result = av_read_frame(demux, packet)) >= 0) {
		if (packet->stream_index == index) {
			check(avcodec_send_packet(decoder, packet), "send packet");
			read_frames(decoder, stream, frame, &count, 0);
		}
		av_packet_unref(packet);
	}
	require(result == AVERROR_EOF, "container EOF");
	check(avcodec_send_packet(decoder, NULL), "flush decoder");
	read_frames(decoder, stream, frame, &count, 1);
	require(count == FRAMES, "complete frame count");
	av_packet_free(&packet);
	av_frame_free(&frame);
	avcodec_free_context(&decoder);
	avformat_close_input(&demux);
	av_log_set_callback(av_log_default_callback);
	require(!atomic_load(&decode_diagnostic), "clean decoder/container diagnostics");
	printf("PASS FFmpeg %s: %d exact frames, timestamps, encoder/decoder drain, EOF\n",
	    av_version_info(), count);
}

int
main(int argc, char **argv)
{
	struct stat metadata;
	uintmax_t expected_size = 0;
	char *end;
	const char *path;

	alarm(30);
	require(argc == 2 || (argc == 4 && strcmp(argv[1], "--read") == 0),
	    "usage: ffmpeg-contract FILE | --read FILE TRUSTED_BYTE_LENGTH");
	require(strcmp(av_version_info(), "9.0.2") == 0, "runtime version 9.0.2");
	require(avcodec_version() == LIBAVCODEC_VERSION_INT &&
	    avformat_version() == LIBAVFORMAT_VERSION_INT &&
	    avutil_version() == LIBAVUTIL_VERSION_INT, "header/runtime agreement");
	if (argc == 2) {
		encode(argv[1]);
		path = argv[1];
	} else {
		path = argv[2];
		errno = 0;
		expected_size = strtoumax(argv[3], &end, 10);
		require(errno == 0 && *end == '\0' && expected_size > 0,
		    "positive trusted fixture size");
	}
	require(stat(path, &metadata) == 0 && S_ISREG(metadata.st_mode), "regular input file");
	if (argc == 4)
		require(metadata.st_size >= 0 && (uintmax_t)metadata.st_size == expected_size,
		    "complete fixture byte length, including container trailer");
	decode(path);
	return 0;
}
