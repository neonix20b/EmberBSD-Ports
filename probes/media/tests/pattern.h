/* SPDX-License-Identifier: MIT */
#ifndef MEDIA_PATTERN_H
#define MEDIA_PATTERN_H
#define WIDTH 64
#define HEIGHT 48
#define FRAMES 12
#define FPS 25
static unsigned char
pixel(int frame, int x, int y)
{
	return (unsigned char)((frame * 7 + x * 3 + y * 5) & 255);
}
#endif
