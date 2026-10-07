# Common userspace migration for Plasma Mobile

The endpoint is the [Mobile runtime workflow](../README.md#required-runtime-result),
including real OpenGL rendering and live window switching. A source export,
successful compilation or an offscreen QML import is not that result.

## Preserve one dependency stack

Use the existing GCC 16.2 candidate and the common Python 3.14.8,
Meson 1.12.1, LLVM/Clang/LLD 23.1.2 recipes. Retain the selected LLVM targets,
static development components and shared LLVM runtime. Do not add an older
LLVM, Python or C++ runtime to satisfy one application.

Build the common candidate in one temporary native staging root, with the
final `/usr/pkg` prefix and its own package database. Bootstrap tools may
come from the recorded working system; identify and replace their old
runtime dependencies before acceptance. The existing system is recovery
state until the candidate and affected consumers pass. Do not copy its
entire dependency database into a partial candidate or create SONAME aliases.

## Resource budget and ownership

Coordinate with any running compiler suite and kernel/DRM work before
allocating storage, installing packages or rebooting a shared VM. Preserve
the original compiler test tree, status and logs. Updating unchanged GCC
sources or rebuilding its candidate does not fix OS defects found by tests.

For the current small AArch64 build machine, the initial estimate is one
additional sparse 24 GiB scratch disk, including a 4 GiB swap file, plus
existing scratch space for archives/packages. This is a planning budget,
not a measured LLVM or Qt peak:

| Concurrent use | Budget |
| --- | --- |
| Bootstrap and installed candidate closure | 5–7 GiB |
| One LLVM source extraction | About 2 GiB |
| One release object tree | Up to 6 GiB |
| Current package DESTDIR | Up to 2 GiB |
| Packages and rollback material | About 2 GiB; archive cache may use existing scratch |
| Swap | 4 GiB |
| Free scratch reserve | At least 2 GiB |

Use one build/test worker, release flags without debug information or LTO,
and one LLVM/Clang/Qt object tree at a time. Single-process memory peaks are
not yet measured; swap is needed before attempting large links in a 4 GiB VM.
Record actual RAM, swap and disk peaks. Stop the owned build at the reserve
threshold rather than filling a shared filesystem.

Retain at least 1 GiB free on the guest root, 2 GiB on its build filesystem
and 16 GiB actual free on the host filesystem. Include growth of every VM
image, host swap and source cache in the host calculation. Verify the new
disk's identity and capacity before formatting. Do not preallocate its full
logical capacity or remove unrelated data to make room.

Only clean an owned object tree after its package, manifest and required
results have been saved. A resource-guard exit preserves failed status,
logs and completed packages; it is not a request for an automatic retry.

## Native sequence

1. Save the installed package inventory, source revisions, configurations,
   dependency metadata and verified rollback packages. Determine the exact
   candidate and package-database locations before installing anything.
2. Complete the active compiler test run. Coordinate a matched kernel and
   system-library update with the OS owner. The currently identified FP-state,
   memfd and narrow-CAS fixes need installed native checks; a source fix alone
   cannot establish correct platform behavior.
3. Build/package the common Python and Meson closure in staging. Test real
   installed extensions, metadata, ELF paths and the existing common-profile
   consumer contracts. Old Python consumers must migrate together.
4. Build/package LLVM, lit, Clang and LLD with GCC 16. Preserve native test and
   package failures. Verify generated exports, static development components,
   compiler defaults and installed ELF/runtime closure before cleaning objects.
5. Rebuild the C++ dependencies, including ICU and double-conversion, then the
   common Mesa 26.2.4 graphics closure, Qt 6.12 and Frameworks 6.30. Run native
   package/check-files, installed C++ consumers, QDoc and Qt plugin checks.
6. Rebuild KWin 6.7.5 with global shortcuts, Workspace and Mobile against that
   same closure. Recheck temporary GCC12 STL patches for removal. Remove the
   memfd workaround only after the installed OS regression passes.
7. Run the real OpenGL/KMS Mobile workflow in the candidate, including two
   Wayland applications, live thumbnails, switching, on-screen keyboard input,
   text saving, exit and a second clean launch. Coordinate display ownership.
8. Test affected shared-library consumers. Choose the final storage placement
   from the measured candidate size. Verify rollback, then perform the common
   package switch in one maintenance window. Retire temporary old dependencies
   after those checks; the staging root is not a permanent per-application OS.

## Source integration still needed before step 5

The toolkit is a source candidate, not a closed installable package set.
The inherited Qt Multimedia and KFileMetadata recipes still refer to pkgsrc's
FFmpeg 8. They must move together to the common FFmpeg 9 package integration;
the [current media probe](../../media/README.md) does not yet provide that
general-purpose package. Its deliberately limited codec configuration must
not silently replace desktop multimedia functionality.
The private toolkit MAKECONF therefore rejects these two consumer recipes
and older FFmpeg packages until that integration is prepared. This blocker
must be removed together with the actual recipe/buildlink/PLIST migration.

Likewise, the modern Mesa source probe needs package integration with one
EGL/GL ABI. The toolkit rejects the inherited Mesa21 recipe, requires
Mesa26.2.4 and disables built-in GL/GLU selection. The separately built
BluezQt/NetworkManagerQt/ModemManagerQt
clients need the same KF6.30/GCC16 migration. Do not run a recursive package
upgrade from this export before resolving these dependencies. Full native
PLIST generation/check-files remains required for every updated recipe.
