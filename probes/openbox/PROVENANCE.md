# Openbox probe provenance

Openbox 3.6.1 is the release listed on the
[upstream download page](https://openbox.org/download), checked 2026-10-07.
Its age is an upstream release fact; this probe does not claim active
upstream maintenance. The archive is downloaded from that page's original
release URL and verified before extraction with [sources.tsv](sources.tsv).
No source archives or build products are stored in this repository.

- Archive: https://openbox.org/dist/openbox/openbox-3.6.1.tar.gz
- SHA256: `8b4ac0760018c77c0044fab06a4f0c510ba87eae934d9983b10878483bde7ef7`
- SHA512: `5e6f4a214005bea8b26bc8959fe5bb67356a387ddd317e014f43cb5b5bf263ec617a5973e2982eb76a08dc7d3ca5ec9e72e64c9b5efd751001a8999b420b1ad0`
- Size: 962665 bytes.

The independently recorded SHA512 and size match
[pkgsrc distinfo](https://github.com/NetBSD/pkgsrc/blob/fff4deb639a1a640476203c80f752fb77b6cb14b/wm/openbox/distinfo).
The packaging reference is the repository's pinned pkgsrc revision
`fff4deb639a1a640476203c80f752fb77b6cb14b`.

## License and authorship

Openbox's README and source headers license it under GPL version 2 or,
at the recipient's option, a later version. Original
[COPYING](LICENSES/COPYING) and [AUTHORS](LICENSES/AUTHORS) are copied
unchanged from the verified archive. Main credits include Mikael Magnusson,
Dana Jansens, Derek Foreman, Tore Anderson and Audun Hove; individual source
copyright notices remain in the extracted tree.

The pkgsrc patches retain their original content and CVS identifiers:

- `patch-ab`, revision 1.5, fixes translation-file installation commands.
- `patch-data_autostart_openbox-xdg-autostart`, revision 1.1, ports the
  existing upstream XDG autostart helper to Python 3. It is not a new
  EmberBSD Python utility. Upstream acceptance is not established for
  either copied patch.

The shell builder and its configuration are AI-assisted EmberBSD work.
`native-pkg-config.sh` follows this repository's Enlightenment probe: it
selects native `libintl.so.1`, matching installed GLib, instead of loading
pkgsrc gettext's competing ABI. The upstream autostart helper's shebang
is changed to the selected `PYTHON` path during source preparation.
These adaptations have not been submitted or accepted upstream.
