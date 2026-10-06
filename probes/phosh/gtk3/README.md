# GTK3 pkgsrc patch provenance

The ten files in [patches/](patches/) were copied unchanged from
[NetBSD pkgsrc, branch pkgsrc-2026Q2, x11/gtk3/patches](https://github.com/NetBSD/pkgsrc/tree/pkgsrc-2026Q2/x11/gtk3/patches)
on 2026-10-06. They are applied to GTK 3.24.52 by
[`build-support.sh`](../build-support.sh). The GTK archive URL and SHA256
are pinned in [the support manifest](../support-sources.tsv).

[provenance.tsv](provenance.tsv) records every patch's filename, full-file
SHA256, original Git blob ID and original download URL. All ten local
Git blob IDs match the source repository's directory listing. All ten
files were also compared byte-for-byte with the official branch on
2026-10-06. The SHA256 values include the original RCS identifiers,
comments, whitespace and line endings; the copied files were not cleaned
up or reformatted.

The Git blob column pins content independently of later branch changes.
The corresponding immutable source object is available at
`https://api.github.com/repos/NetBSD/pkgsrc/git/blobs/<git_blob>`.

| Patch | Preserved purpose |
|---|---|
| `patch-gdk_wayland_gdkdevice-wayland.c` | Wayland protocol button constants on systems without evdev headers |
| `patch-gdk_x11_gdkscreen-x11.h` | Avoid duplicate `GdkX11Monitor` typedef |
| `patch-gdk_x11_gdkwindow-x11.h` | Xfixes/libXi header ordering |
| `patch-gtk_a11y_gtkaccessibility.c` | Optional ATK bridge, paired with Meson changes |
| `patch-gtk_fallback-c89.c` | Avoid collisions with native math declarations |
| `patch-gtk_gtkfontchooserwidget.c` | Use FreeType's public include macros |
| `patch-gtk_gtklabel.c` | Validate the label before dereferencing it |
| `patch-meson.build` | Optional ATK bridge configuration |
| `patch-meson_options.txt` | ATK bridge build option |
| `patch-tests_gtkgears.c` | Avoid the compiler's `sincos` builtin detection mismatch |

These are downstream pkgsrc patches, not a claim of GTK upstream
acceptance. In particular, `patch-gtk_gtklabel.c` explicitly records that
GTK upstream rejected that patch and that Glade was adjusted instead.
That note remains unchanged. Other original issue links and NetBSD
revision/author identifiers also remain intact.

No new C implementation was added to these files for EmberBSD. The
selection, support helper and provenance documentation were AI-assisted.
The GTK files retain their original authorship and LGPL notices.
GTK's original license text remains in the verified source archive;
the patch copies do not relicense the affected GTK code.

For build results, runtime evidence and remaining hardware/service
limits, see [the support-library documentation](../support.md).
