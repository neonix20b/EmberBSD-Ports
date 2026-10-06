/* SPDX-License-Identifier: MIT */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <gst/gst.h>
#include <gst/app/gstappsrc.h>
#include <gst/app/gstappsink.h>
#include "pattern.h"

static void
require(int ok, const char *what)
{
	if (!ok) {
		fprintf(stderr, "FAIL GStreamer: %s\n", what);
		exit(1);
	}
}

static void
check_plugin(const char *name)
{
	GstElementFactory *factory = gst_element_factory_find(name);
	GstPlugin *plugin;

	require(factory != NULL, name);
	plugin = gst_plugin_feature_get_plugin(GST_PLUGIN_FEATURE(factory));
	require(plugin && strcmp(gst_plugin_get_version(plugin), "1.28.7") == 0,
	    "plugin version matches selected profile");
	printf("plugin %s: %s\n", name, gst_plugin_get_filename(plugin));
	gst_object_unref(plugin);
	gst_object_unref(factory);
}

static GstMessage *
terminal_message(GstElement *pipeline)
{
	GstBus *bus = gst_element_get_bus(pipeline);
	GstMessage *message = gst_bus_timed_pop_filtered(bus, 5 * GST_SECOND,
	    GST_MESSAGE_ERROR | GST_MESSAGE_EOS);

	gst_object_unref(bus);
	require(message != NULL, "terminal bus message deadline");
	return message;
}

static void
file_input(const char *path)
{
	FILE *output = fopen(path, "wb");
	GError *error = NULL;
	GstElement *pipeline, *source, *sink;
	GstSample *sample;
	GstBuffer *buffer;
	GstMessage *message;
	GstMapInfo map;
	int i, x, y;

	require(output != NULL, "open raw fixture");
	for (i = 0; i < FRAMES; i++)
		for (y = 0; y < HEIGHT; y++)
			for (x = 0; x < WIDTH; x++)
				require(fputc(pixel(i, x, y), output) != EOF, "write raw fixture");
	require(fclose(output) == 0, "close raw fixture");
	pipeline = gst_parse_launch("filesrc name=file ! rawvideoparse "
	    "format=gray8 width=64 height=48 framerate=25/1 ! "
	    "appsink name=sink sync=false max-buffers=2", &error);
	require(pipeline != NULL && error == NULL, "construct file pipeline");
	source = gst_bin_get_by_name(GST_BIN(pipeline), "file");
	sink = gst_bin_get_by_name(GST_BIN(pipeline), "sink");
	require(source && sink, "file endpoints");
	g_object_set(source, "location", path, NULL);
	require(gst_element_set_state(pipeline, GST_STATE_PLAYING) != GST_STATE_CHANGE_FAILURE,
	    "start file pipeline");
	for (i = 0; i < FRAMES; i++) {
		sample = gst_app_sink_try_pull_sample(GST_APP_SINK(sink), 5 * GST_SECOND);
		require(sample != NULL, "file sample deadline");
		buffer = gst_sample_get_buffer(sample);
		require(GST_BUFFER_PTS(buffer) == gst_util_uint64_scale(i, GST_SECOND, FPS),
		    "file timestamp");
		require(gst_buffer_map(buffer, &map, GST_MAP_READ), "map file frame");
		require(map.size == WIDTH * HEIGHT, "file frame size");
		for (y = 0; y < HEIGHT; y++)
			for (x = 0; x < WIDTH; x++)
				require(map.data[y * WIDTH + x] == pixel(i, x, y), "file pixel");
		gst_buffer_unmap(buffer, &map);
		gst_sample_unref(sample);
	}
	require(gst_app_sink_try_pull_sample(GST_APP_SINK(sink), 5 * GST_SECOND) == NULL &&
	    gst_app_sink_is_eos(GST_APP_SINK(sink)), "file appsink EOS");
	message = terminal_message(pipeline);
	require(GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS, "file pipeline EOS");
	gst_message_unref(message);
	(void)gst_element_set_state(pipeline, GST_STATE_NULL);
	gst_object_unref(source);
	gst_object_unref(sink);
	gst_object_unref(pipeline);
}

static void
round_trip(int bad_caps)
{
	GError *error = NULL;
	GstElement *pipeline, *source, *sink;
	GstCaps *caps;
	GstBuffer *buffer;
	GstSample *sample;
	GstMessage *message;
	GstMapInfo map;
	int i, x, y;

	pipeline = gst_parse_launch("appsrc name=src format=time ! videoconvert ! "
	    "video/x-raw,format=BGR ! appsink name=sink sync=false max-buffers=2", &error);
	require(pipeline != NULL && error == NULL, "construct pipeline");
	source = gst_bin_get_by_name(GST_BIN(pipeline), "src");
	sink = gst_bin_get_by_name(GST_BIN(pipeline), "sink");
	require(source && sink, "application endpoints");
	caps = gst_caps_new_simple(bad_caps ? "application/x-ember-invalid" : "video/x-raw",
	    "format", G_TYPE_STRING, "GRAY8", "width", G_TYPE_INT, WIDTH,
	    "height", G_TYPE_INT, HEIGHT, "framerate", GST_TYPE_FRACTION, FPS, 1, NULL);
	gst_app_src_set_caps(GST_APP_SRC(source), caps);
	gst_caps_unref(caps);
	require(gst_element_set_state(pipeline, GST_STATE_PLAYING) != GST_STATE_CHANGE_FAILURE,
	    "start pipeline");
	for (i = 0; i < (bad_caps ? 1 : FRAMES); i++) {
		buffer = gst_buffer_new_allocate(NULL, WIDTH * HEIGHT, NULL);
		require(buffer && gst_buffer_map(buffer, &map, GST_MAP_WRITE), "map input");
		for (y = 0; y < HEIGHT; y++)
			for (x = 0; x < WIDTH; x++)
				map.data[y * WIDTH + x] = pixel(i, x, y);
		gst_buffer_unmap(buffer, &map);
		GST_BUFFER_PTS(buffer) = gst_util_uint64_scale(i, GST_SECOND, FPS);
		GST_BUFFER_DURATION(buffer) = GST_SECOND / FPS;
		require(gst_app_src_push_buffer(GST_APP_SRC(source), buffer) == GST_FLOW_OK,
		    "push buffer"); /* appsrc owns buffer even on failure. */
		if (bad_caps)
			break;
		sample = gst_app_sink_try_pull_sample(GST_APP_SINK(sink), 5 * GST_SECOND);
		require(sample != NULL, "sample deadline");
		buffer = gst_sample_get_buffer(sample);
		require(GST_BUFFER_PTS(buffer) == gst_util_uint64_scale(i, GST_SECOND, FPS) &&
		    GST_BUFFER_DURATION(buffer) == GST_SECOND / FPS, "sample timestamp and duration");
		require(gst_buffer_map(buffer, &map, GST_MAP_READ), "map output");
		require(map.size == WIDTH * HEIGHT * 3, "BGR buffer size");
		for (y = 0; y < HEIGHT; y++)
			for (x = 0; x < WIDTH; x++) {
				size_t p = (size_t)(y * WIDTH + x) * 3;
				require(map.data[p] == pixel(i, x, y) &&
				    map.data[p + 1] == pixel(i, x, y) &&
				    map.data[p + 2] == pixel(i, x, y), "converted pixels");
			}
		gst_buffer_unmap(buffer, &map);
		gst_sample_unref(sample);
	}
	if (!bad_caps) {
		require(gst_app_src_end_of_stream(GST_APP_SRC(source)) == GST_FLOW_OK,
		    "send EOS");
		sample = gst_app_sink_try_pull_sample(GST_APP_SINK(sink), 5 * GST_SECOND);
		require(sample == NULL && gst_app_sink_is_eos(GST_APP_SINK(sink)),
		    "appsink complete EOS without extra frame");
	}
	message = terminal_message(pipeline);
	if (bad_caps) {
		gchar *debug = NULL;
		require(GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR, "invalid caps error");
		gst_message_parse_error(message, &error, &debug);
		require(error && error->domain == GST_STREAM_ERROR && debug &&
		    strstr(debug, "not-negotiated"), "caps negotiation error reason");
		g_error_free(error);
		g_free(debug);
	} else {
		require(GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS, "pipeline EOS");
	}
	gst_message_unref(message);
	require(gst_element_set_state(pipeline, GST_STATE_NULL) != GST_STATE_CHANGE_FAILURE,
	    "stop pipeline");
	gst_object_unref(source);
	gst_object_unref(sink);
	gst_object_unref(pipeline);
}

int
main(int argc, char **argv)
{
	guint major, minor, micro, nano;

	alarm(45);
	gst_init(&argc, &argv);
	require(argc == 2, "usage: gstreamer-contract RAW_FIXTURE");
	gst_version(&major, &minor, &micro, &nano);
	require(major == 1 && minor == 28 && micro == 7 && nano == 0,
	    "runtime version 1.28.7");
	check_plugin("appsrc");
	check_plugin("appsink");
	check_plugin("videoconvert");
	check_plugin("rawvideoparse");
	check_plugin("filesrc");
	round_trip(0);
	round_trip(1);
	file_input(argv[1]);
	gst_deinit();
	puts("PASS GStreamer 1.28.7: exact conversion, file frames/timestamps, appsrc/appsink EOS, bad caps");
	return 0;
}
