# GObject Introspection for EmberBSD cross builds

The graphics profile supplies `gobject-introspection-1.86.0nb5`, built on
macOS for EmberBSD/AArch64 with GCC16, Python 3.14.8 and GLib 2.90.1.
Its complete selected pkgsrc payload is preserved: library, tools, Python
scanner extension, GIRepository GIR/typelib, headers and test sources.
The GLib-family GIR files belong to the separate `glib2-introspection` package;
building them here does not install that separate package.

The original [GNOME archive](https://download.gnome.org/sources/gobject-introspection/1.86/gobject-introspection-1.86.0.tar.xz)
has SHA256 `920d1a3fcedeadc32acff95c2e203b319039dd4b4a08dd1a2dfd283d19c0b9ae`.
The [recipe](../recipes/devel/gobject-introspection/Makefile) preserves the
pinned pkgsrc import and attribution. EmberBSD's patches are not submitted
upstream. They separate native generators from target libraries and retain
installed test source data that upstream omits during cross builds.

## Build and execution roles

Use the [common graphics cross profile](profile.md) with an
[EmberBSD sysroot](../../common-build-tools/cross/sysroot.md). A matching native
GI 1.86.0 is a declared tool dependency. Meson runs native Python and native
`g-ir-scanner`/`g-ir-compiler`; pkgsrc's target sysconfig remains responsible
for Python headers, extension ABI and installed `/usr/pkg/bin/python3.14`
shebangs. A Meson native machine file keeps its C compiler on macOS.
Cross `readelf` obtains ELF SONAMEs instead of invoking a host loader.

GType discovery executes small cross-built queries on an authorized EmberBSD
AArch64 VM or board over SSH. The supplied runner resolves target ELF libraries
from the build tree and sysroot, rejects incompatible/conflicting providers,
and transfers copies into a newly allocated private temporary directory.
It checks hashes before and after execution, limits each query to 60 seconds,
disables core dumps and removes the allocated directory. It installs no package
and changes no base system. This is actual target execution, not a host GType
substitute. A user with temporary-directory execution permission is sufficient.

Create an existing private cache outside the sysroot and a private JSON file:

```json
{
  "build_root": "/absolute/work",
  "sysroot": "/absolute/target-sysroot",
  "cache": "/absolute/query-cache",
  "readelf": "/absolute/cross-tools/bin/aarch64--netbsd-readelf",
  "ssh": "builder@ember-target.local"
}
```

The target must already be accessible with noninteractive SSH and a verified
host key. It needs `tar`, `sha256`, `timeout` and its compatible base loader.
The JSON must agree with the recipe's work directory, sysroot and inspection
tool. Add these private MAKECONF settings:

```make
EMBERBSD_GI_RUBY=/absolute/native/ruby
EMBERBSD_GI_QUERY_CONFIG=/absolute/private/query.json
```

Then use ordinary host `bmake ... package install` for the exported
`devel/gobject-introspection` recipe. `install` populates only the private
cross sysroot. Do not set `gi_cross_pkgconfig_sysroot_path`: pkgsrc's pkgconf
already roots target include/library paths, so a second prefix duplicates it.
Keep diagnostic query logs and manifests; successful runs remove transferred
copies and archives. Failed cleanup is an error and reports the exact directory.
XML is published to the scanner only after successful cleanup and unchanged
local source hashes. The scanner still performs its ordinary XML parsing.

## Acceptance and limits

The normal package passes PLIST, interpreter, RPATH, PIE/RELRO, shared-library
and work-reference checks. All 180 payload files/links match the installed
package; its 186 recorded entries include six metadata files. Actual target
queries produce GLib, GModule, GObject, Gio and GIRepository metadata.
On CM5, unchanged upstream `gthash-test` passes its build/retrieve case;
`cmph-bdz-test` passes ordinary and packed search. These use the selected
current GLib and EmberBSD libc in temporary directories.

Accepted package SHA256:
`24c970a890a14083bfdae22426515a12023aea7901dc59fc7f78699fde0cf83f`.
The installed regular-file manifest has SHA256
`e7dedd45cc6eb3d6cc76cc42b6b0a5d33b55b231cf18c54194e6930c83f074c1`.

`tests/gi-query-contract.rb CROSS_TOOLS NEW_WORK` builds real AArch64 ELF
fixtures and checks provider aliases, SONAME inspection and seven refusals
before SSH. Injected transfer, query, readback, invalid-output, cleanup and
input-change failures prove that failed runs publish no XML. A successful
transport fixture publishes it only at the end. These transport fixtures are
separate from the actual CM5 execution. `tests/export.sh NEW_WORK` checks all
six profile compositions and the required recipe, helper and patch inputs.
The final export passed all six compositions and 75 preflight refusals.

The installed target Python scanner and its complete upstream suite have not
yet been accepted on a board. Full current librsvg, its CLI/pixbuf integration,
and a complete Wayland compositor session remain separate work. This package
does not establish hardware GPU or NPU execution.
