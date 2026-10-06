# Plasma Mobile graphics contract

Source baseline: original KDE KWin 6.7.5 and Plasma Mobile 6.7.5 archives.
The mobile-effect restrictions below are source findings. The separate
QPainter window/input test passed on NetBSD 11 aarch64 on 2026-10-06.

## QPainter scope

The isolated test uses the nested X11 backend with `KWIN_COMPOSE=Q`,
`QT_QUICK_BACKEND=software`, and an explicitly empty `KWIN_RENDER_NODES`.
It needs an X server with Present and shared-pixmap SHM support. It does not
open a DRM device or claim hardware rendering support.

`scripts/check-nested.sh` creates a private D-Bus session, Xvfb display and
runtime/config/cache directories. A native Qt Widgets client must report the
Wayland platform, render a window and receive `emberbsd` through XTest events
delivered to the nested compositor. The test records KWin's support information,
the client receipt and an XWD frame. It stops only its own recorded processes.
The native run produced both receipt lines, a visually checked window frame,
and QPainter support information. All owned processes and sockets were cleaned
up. This proves the basic window/input route; it does not prove Plasma Mobile
effects.

## Requirements for the actual mobile switcher

Plasma Mobile's `kwin/mobiletaskswitcher/package/contents/ui/main.qml` uses
`SceneEffect`. KWin's `src/effect/quickeffect.cpp` enables `QuickSceneEffect`
only for `OpenGLCompositing`. Its `src/scripting/windowthumbnailitem.cpp`
also requires the OpenGL compositor and a Qt Quick backend other than
`software` or `softwarecontext` to create live window thumbnails. The mobile
switcher's `Task.qml` uses those thumbnails.

Mobile's `components/mobileshell/qml/homescreen/BlurEffect.qml` uses
ShaderEffectSource, FastBlur and OpacityMask. Qt Quick's software adaptation
cannot render ShaderEffect. See the official Qt 6.11 documentation:
https://doc.qt.io/qt-6.11/qtquick-visualcanvas-adaptations-software.html

Changing the supported-effect predicate alone cannot supply these features.
The QPainter route is useful for a basic shell/input check but does not meet
the complete mobile switcher contract.

## Next graphics-stack acceptance check

The shared Mesa/DRM stack should demonstrate all of the following together:

1. One compatible EGL/GL ABI for Qt, KWin and their libraries.
2. KWin reports OpenGL compositing and Qt Quick uses its OpenGL backend.
3. Two real Wayland clients render and update live window thumbnails.
4. The unmodified mobile switcher opens, selects a window and closes.
5. GBM allocation, EGLImage and buffer export/import work along the selected
   native KMS path. An isolated EGL readback test does not establish this.

Native KMS is the intended integration path. Nested X11 OpenGL additionally
needs functioning DRI3 discovery/import, which is not established by the
QPainter probe. KWin 6.7.5 obtains its nested X11 RenderDevice from DRI3 and
uses GBM/EGL swapchains for OpenGL.

The existing private Mesa installation has different EGL/GL SONAMEs from
the packaged Qt stack. Mixing its DSOs into this probe is not supported.

The packaged Vulkan loader also needs rebuilding: it imports libc `alloca`
instead of using compiler stack allocation. KWin's dynamic-dispatch patch
removes the mandatory loader DSO from the QPainter process, which creates no
RenderDevice. This is not a Vulkan loader fix or a Vulkan runtime result.
