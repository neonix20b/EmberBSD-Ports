-- SPDX-License-Identifier: BSD-2-Clause
-- Exercise the Lua 5.4 coroutine API and awesome's actual rendering bindings.
assert(_VERSION == 'Lua 5.4')
local lgi = require('lgi')
assert(lgi._VERSION == '0.9.2')
local GLib, Gio = lgi.GLib, lgi.Gio
local cairo, Pango, PangoCairo = lgi.cairo, lgi.Pango, lgi.PangoCairo
local GdkPixbuf = lgi.GdkPixbuf
assert(Gio.FileType.REGULAR ~= nil)
assert(Gio.FileCreateFlags.NONE ~= nil)
local path = assert(arg[1], 'PNG output path required')
local surface = cairo.ImageSurface.create(cairo.Format.ARGB32, 160, 48)
local cr = cairo.Context(surface)
cr:set_source_rgb(0.15, 0.2, 0.3)
cr:paint()
cr:set_source_rgb(1, 1, 1)
local layout = PangoCairo.create_layout(cr)
layout.font_description = Pango.FontDescription.from_string('Sans 12')
layout.text = 'EmberBSD Lua 5.4'
local width, height = layout:get_pixel_size()
assert(width > 0 and height > 0)
PangoCairo.show_layout(cr, layout)
assert(surface:write_to_png(path) == 'SUCCESS')
local image = GdkPixbuf.Pixbuf.new_from_file(path)
assert(image.width == 160 and image.height == 48)
assert(Gio.File.new_for_path(path):query_exists())

local loop = GLib.MainLoop()
local calls, expired = 0, false
local watchdog = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, function()
    expired = true
    loop:quit()
    return false
end)
local coro = coroutine.create(function()
    calls = calls + 1
    coroutine.yield(true)
    calls = calls + 1
    loop:quit()
    return false
end)
GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, coro)
loop:run()
if not expired then GLib.source_remove(watchdog) end
assert(not expired, 'LGI coroutine callback timed out')
assert(calls == 2 and coroutine.status(coro) == 'dead')
collectgarbage('collect')
print('PASS: Lua 5.4, LGI enums, Cairo/Pango/GdkPixbuf, Gio, coroutine callbacks')
