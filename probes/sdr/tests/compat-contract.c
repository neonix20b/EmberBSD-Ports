/* SPDX-License-Identifier: MIT */
#include <iio.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); return 1; } } while (0)
int
main(int argc, char **argv)
{
	struct iio_context *ctx;
	struct iio_device *dev, *phy;
	struct iio_channel *i, *q, *lo;
	struct iio_buffer *buf;
	unsigned major, minor, n;
	char tag[8], bad[32];
	long long freq = 0;
	CHECK(argc == 2);
	iio_library_get_version(&major, &minor, tag);
	CHECK(major == 1 && minor == 0);
	ctx = iio_create_context_from_uri(argv[1]);
	CHECK(ctx != NULL);
	CHECK(iio_context_set_timeout(ctx, 250) == 0);
	dev = iio_context_find_device(ctx, "cf-ad9361-lpc");
	phy = iio_context_find_device(ctx, "ad9361-phy");
	CHECK(dev != NULL && phy != NULL);
	lo = iio_device_find_channel(phy, "altvoltage0", true);
	CHECK(lo != NULL);
	CHECK(iio_channel_attr_write_longlong(lo, "frequency", 916000000) == 0);
	CHECK(iio_channel_attr_read_longlong(lo, "frequency", &freq) == 0 && freq == 916000000);
	CHECK(iio_channel_attr_read(lo, "missing_attribute", bad, sizeof(bad)) < 0);
	i = iio_device_find_channel(dev, "voltage0", false);
	q = iio_device_find_channel(dev, "voltage1", false);
	CHECK(i != NULL && q != NULL);
	iio_channel_enable(i);
	iio_channel_enable(q);
	buf = iio_device_create_buffer(dev, 64, false);
	CHECK(buf != NULL && iio_buffer_step(buf) == 4);
	CHECK(iio_buffer_refill(buf) == 256);
	for (n = 0; n < 64; n++) {
		int16_t iv, qv;
		iio_channel_convert(i, &iv, (char *)iio_buffer_first(buf, i) + 4 * n);
		iio_channel_convert(q, &qv, (char *)iio_buffer_first(buf, q) + 4 * n);
		CHECK(iv == (int)(n % 31) - 15 && qv == 100 - (int)(n % 17));
	}
	iio_buffer_destroy(buf);
	iio_context_destroy(ctx);
	puts("PASS official libiio1 compat: version, attributes, missing attribute, 64 exact IQ samples");
	return 0;
}
