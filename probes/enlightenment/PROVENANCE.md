# Enlightenment probe provenance

The original archives are downloaded from Enlightenment's release server.
The source manifests pin SHA256; the archives were also checked against
SHA512 in the pkgsrc-wip distinfo files below. No archives or binaries are
stored in this repository.

- EFL 1.28.1: https://download.enlightenment.org/rel/libs/efl/efl-1.28.1.tar.xz
- Enlightenment 0.27.1: https://download.enlightenment.org/rel/apps/enlightenment/enlightenment-0.27.1.tar.xz
- Packaging reference: [NetBSD/pkgsrc-wip at 60460008d0c770590e46fc229035b8e454472a80](https://github.com/NetBSD/pkgsrc-wip/tree/60460008d0c770590e46fc229035b8e454472a80),
  `efl` and `enlightenment-current`, retrieved 2026-10-06.

The copied pkgsrc `patch-*` files retain their original headers and content.
Local exceptions are listed below.
Their upstream acceptance status is recorded in each original header.
The EFL NetBSD changes were accepted in upstream pull request 130;
Enlightenment's NetBSD support was accepted in pull request 139. These
releases predate those changes, so the backports remain necessary.
Other packaging adaptations are not claimed to be upstream changes.

The NetBSD port credits Robert Bagdan, Matthew Danielson, GSoC contributor
moihack and mentors leot and nia; upstream integration involved Carsten
Haitzler. See the [NetBSD project report](https://blog.netbsd.org/tnf/entry/gsoc2026_enlightenment_2)
and the pinned pkgsrc-wip history for individual patch authorship.

The private-profile build/run helpers are AI-assisted EmberBSD work.
Local changes are not claimed to have been submitted or accepted upstream.

`LICENSES/efl/COPYING` maps EFL's components to their original license
texts, retained alongside it. EFL aggregates BSD, LGPL, GPL and other
compatible components; do not describe the entire library stack as BSD.

Local additions:

- `patches/efl/patch-dbus-services_meson.build`: install the Ethumb session
  service under EFL's selected prefix, instead of dbus's system prefix.
  An ordinary-user private installation otherwise failed with EACCES.
- `patches/efl/lua54.patch`: adapt Edje/Evas to the operating system's
  Lua 5.4. This includes real API and numeric-conversion changes; changing
  only the accepted version range would break themes. Optional Elua and
  generated Lua bindings remain explicitly unsupported with Lua >=5.3.
  No separate older Lua is required by this profile.

The latest stable EFL release was 1.28.1 when this probe was prepared.
Upstream master `b573583b0712eabf58278659e5cfa663a1f52d1b` identified itself
as 1.28.99 and still restricted Lua to versions below 5.3. The probe keeps
one stable EFL source with the required patches, rather than installing
both stable/development EFL and an additional Lua runtime.

- `patches/enlightenment/private-profile.patch`: add the opt-out
  `system-services` build option and derive an ordinary-user desktop
  profile without hardware, power or lock actions. Upstream's normal
  build remains enabled by default. Actual-source policy tests exercise
  both modes and profile filtering.
- `patches/enlightenment/patch-src_bin_e__start__main.c`: propagate normal
  and terminal-error window-manager exit statuses. Failed `execv` returns
  the launcher's terminal error 101 instead of successful logout.
- `session-processes.c` and its process-scope fixtures are new AI-assisted
  EmberBSD work under BSD-2-Clause; see `LICENSES/EMBERBSD-HELPERS`.
  They use NetBSD process/environment sysctls to clean cooperative
  detached children belonging to a disposable session.
