# Phosh without network control

Apply `phosh-optional-networkmanager.patch` **after**
`phosh-optional-platform.patch`, to Phosh 0.58.0. Add
`-Dnetworkmanager=disabled` to the Meson setup options for the nested
launcher/overview/application-switching experiment.

The feature defaults to `enabled`: the normal build still requires libnm
and builds the upstream network controls. Explicit `auto` may disable
them when libnm is unavailable. `disabled` excludes them even when libnm
is installed. This is a Phosh build profile, not a replacement libnm API
or library.

## Disabled scope

The following implementations are not compiled in this mode:

- Wi-Fi manager, network models, status page and network authentication.
- VPN manager and connectivity/captive-portal manager.
- WWAN backends and their NetworkManager-dependent base, plus cell
  broadcasts. The mm-glib dependency is omitted in this profile.
- Wi-Fi hotspot and mobile-data quick-setting plugins.

The shell's Wi-Fi, VPN, WWAN and connectivity manager getters explicitly
return `NULL`. Built-in callers are excluded with their managers. There
is no asynchronous operation pretending to succeed: those operations
and their controls are absent. External plugins that require network
manager APIs are unsupported in this build profile.

Phosh reports the disabled controls at startup. Applications use the
existing operating-system network; the profile does not reconfigure it. No
Phosh connectivity result is available; neither connected nor offline
is claimed. Existing network configuration is not read or modified.

## UI transformation

The patch adds `src/ui/no-network.xsl`. When network control is disabled,
Meson uses `xsltproc --nonet` to generate the quick-settings and top-panel
templates and a resource manifest. It removes only the Wi-Fi, WWAN, VPN
and connectivity objects, their container children and bindings. Other
controls remain in their existing layouts. The normal build uses the
original templates.

The generated manifest keeps the original resource aliases, so the
unchanged widget template loaders receive the correct variant. The source
templates are preserved; no second hand-maintained UI copy is introduced.
`xsltproc` is an additional build tool for the disabled profile.

## Validation

On 2026-10-06, both transformed XML templates and their actual GLib
resource bundle passed the native NetBSD 11/aarch64 check. All remaining
`bind-source` references resolve: 6 in quick-settings and 8 in top-panel.
The checks preserved the quick-settings box, main settings widget,
clock and status icon container, and found no removed network widgets,
callbacks or bindings.

```sh
sh test-no-network-ui.sh /path/to/patched/phosh-0.58.0
```

The helper requires `xsltproc`, `xmllint` and `glib-compile-resources`.
It uses a fresh temporary directory and does not start a desktop session.
The inspected generated XML had these SHA256 values (libxslt output):

| Template | SHA256 |
|---|---|
| quick-settings-no-network.ui | `309ef5ef210c75672c434d1034e8a31791dee10829908f90d1d454c2304c1e3a` |
| top-panel-no-network.ui | `55f1a84ca742d771d2c6797c10cae2236a90b1f7241315b9b46301db52f96c44` |

A fresh Phosh 0.58.0 build with this disabled profile compiled and
installed on NetBSD 11/aarch64. The nested session displayed its home/app
grid, accepted keyboard search, and launched Gedit; text entry, saving
and the saved contents were verified. Its private session terminated
without stopping the existing GNOME desktop.

These results establish the tested launcher/application workflow.
Application network reachability and external network-control plugins
were not part of that validation. Missing indicators do not establish
an offline or connected state. The enabled Linux profile and the full
upstream Phosh Meson test suite remain unverified.

## Provenance

The source version, archive checksum and license are the same as the
[platform patch](README.md#provenance): unmodified upstream Phosh 0.58.0
with SHA256 `b936af34ebed15b29d4f941c48aa328a47da9c2e51cbf6ef89040a90f522ed73`.
This additional patch and its test are local AI-assisted EmberBSD work,
not submitted to or accepted by upstream. Original copyright and license
notices remain intact. New transformation and test material use
GPL-3.0-or-later.
