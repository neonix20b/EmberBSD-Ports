# Xfce source provenance

The selected desktop is the stable Xfce 4.20 series, confirmed on the
[upstream download page](https://xfce.org/download/) on 2026-10-07.
Individual components receive independent maintenance releases. The
[source manifest](sources.tsv) pins each original archive URL and SHA256;
the builder verifies all downloads before extraction. Source archives,
generated binaries and full logs stay outside this repository.
The Xfce hashes were independently compared with the release server's
`?sha256` responses; all selected archives matched.

The `archive.xfce.org/src/xfce/COMPONENT/4.20/` directories were inspected
on that date. Selected releases are:

| Component | Version |
| --- | --- |
| xfce4-dev-tools | 4.20.0 |
| libxfce4util | 4.20.1 |
| xfconf | 4.20.0 |
| libxfce4ui | 4.20.2 |
| libxfce4windowing | 4.20.7 |
| exo | 4.20.0 |
| garcon | 4.20.0 |
| xfce4-panel | 4.20.8 |
| thunar | 4.20.10 |
| xfce4-settings | 4.20.5 |
| xfdesktop | 4.20.2 |
| xfwm4 | 4.20.0 |
| xfce4-session | 4.20.4 |
| xfce4-appfinder | 4.20.0 |

The optional Mousepad 0.7.0 editor is the latest release in
[its upstream archive](https://archive.xfce.org/src/apps/mousepad/0.7/).
Its [release announcement](https://mail.xfce.org/pipermail/xfce-announce/2026-March/001652.html)
confirms the transition to Meson. It continues to support the installed
GTK3 and GtkSourceView 4 APIs.

Two missing dependency families are built into the same prefix:

- [libwnck 43.3](https://download.gnome.org/sources/libwnck/43/) is GNOME's
  current release. Its archive hash matches the upstream `.sha256sum`.
- [libyaml 0.2.5](https://github.com/yaml/libyaml/releases) is the latest
  stable release; 0.2.6-rc.1 is marked a prerelease. The selected original
  release archive retains its upstream license and source identifiers.

An already installed matching dependency is reused. A different version
causes an explicit stop, so the recipe cannot silently add a second ABI
family alongside an existing package. GTK, GLib, Perl and the rest of the
operating system's dependency stack are not replaced by this probe.

## Packaging reference and local adaptations

The comparison used this repository's pinned
[pkgsrc revision fff4deb639a1a640476203c80f752fb77b6cb14b](https://github.com/NetBSD/pkgsrc/tree/fff4deb639a1a640476203c80f752fb77b6cb14b).
Its Xfce recipes document dependencies and NetBSD conventions. Their
patches that redirect configuration into package example directories
are unnecessary for an ordinary-user prefix and are not copied. The
session's NetBSD suspend/hibernate backend is outside this X11 probe;
those power-management patches are not claimed as implemented support.

No upstream C sources are changed initially. Two existing upstream
Python scripts receive the selected interpreter path during preparation:
`xfce4-dev-tools/scripts/xdt-gen-visibility` and
`xfce4-settings/dialogs/mime-settings/helpers/xfce4-compose-mail`.
The first is required by the upstream build; the latter remains an
optional mail helper. Project-owned helpers use shell and C.

The session configure option `--with-xsession-prefix` selects the same
private prefix as its binaries. Upstream defaults this independent setting
to `/usr`; selecting it explicitly avoids installing a system login entry.

`native-pkg-config.sh` follows the repository's Enlightenment/Openbox
probes and chooses `/usr/lib/libintl.so.1`, the ABI used by installed
GLib. It does not build or install another gettext implementation.
The local scripts and profile choices are AI-assisted EmberBSD work;
none is claimed to have been submitted or accepted upstream.
`prepare-session.sh` derives a private configuration from the installed
upstream defaults. It uses documented kiosk and existing Xfconf properties;
[SESSION.md](SESSION.md) records their source-level behavior and limits.

## Licenses and attribution

Xfce contains GPL and LGPL components; the complete desktop is not BSD
licensed. libwnck is LGPL; libyaml is MIT licensed. Author and license
notices remain in every extracted source tree. On installation, the
builder copies each component's `COPYING*`, `LICENSE*`, `License` and `AUTHORS*`
files unchanged into `share/xfce-probe/provenance/COMPONENT`. Original
headers remain authoritative for individual files and subcomponents.

Preparation, build and runtime evidence are separate.
[Native validation](VALIDATION.md) records the completed build and actual
application workflow on NetBSD 11/AArch64; it does not establish phone or
hardware-accelerated graphics support.

`tests/wnck-consumer.c` is an AI-assisted EmberBSD C helper under the
BSD-2-Clause license indicated in its source. It invokes the installed
library's GObject type API and enumerates actual loaded objects with
NetBSD's `dl_iterate_phdr`. Its companion shell check keeps C API success
separate from the shared toolchain's stricter C++ migration acceptance.
