# Current compiler prerequisites

The GCC profile updates MPC/Texinfo recipes using
`patches/current-prerequisites.patch` and the test harness using
`patches/stable-expect.patch`. These are AI-assisted EmberBSD deltas,
not submitted upstream. Versions are selected from upstream releases, not
from the age of the pkgsrc recipe. Full archive SHA256 values are in
`sources.tsv`; BLAKE2s, SHA512 and byte counts are in the resulting distinfo.

## MPC 1.4.1

[Upstream download page](https://www.multiprecision.org/mpc/download.html)
identifies 1.4.1 as current. The archive uses `.tar.xz`, unlike pkgsrc's 1.3.1.
The upstream signature was checked with the maintainer's key from
<https://www.multiprecision.org/downloads/enge.gpg>, fingerprint
`AD17A21EF8AED8F1CC02DBD9F7D5C9BF765C61E3`. The signature is cryptographically
valid; GnuPG reports the published key expired at the time of this check.
This is recorded rather than claiming a currently trusted certification.

The source retains libtool version-info `7:1:4`, hence runtime major 3.
No earlier MPC package was installed on the preparation host. The recipe
adds the new `lib/pkgconfig/mpc.pc` file. Its inherited Solaris complex-number
workaround is refreshed for `_MPC_HAVE_COMPLEX_H` and `DOUBLE_COMPLEX`.
MPC still requires GMP >=5.0 and MPFR >=4.1; no existing math library update
is implied. Native arithmetic tests and dependency identity remain required.

## Texinfo 7.3

[Upstream release announcement](https://lists.gnu.org/archive/html/info-gnu/2026-03/msg00000.html)
identifies 7.3, released 2026-03-02. It reorganizes `tp/` into `tta/`.
The archive's signature verifies against the GNU release keyring from
<https://ftp.gnu.org/gnu/gnu-keyring.gpg>, fingerprint
`EAF669B31E31E1DECBD11513DDBC579DAB37FBA9` (Gavin Smith).
The isolated verification keyring does not assign personal owner trust.
The inherited top-level configure and gnulib patches apply unchanged.
The default Info path patch is refreshed around the new DJGPP conditional.
Three obsolete patches are removed with these concrete reasons:

- `tp/Texinfo/XS/configure` no longer exists; its iconv checks are in the
  top-level configure, where the existing pkgsrc patch still applies.
- The C parser moved to `tta/C/parsetexi`; the prior patch merely moved a
  C99 loop-variable declaration. Our NetBSD 11 bootstrap compiler supports C99.
- Upstream removed texi2dvi's historical ksh re-exec branch, so the patch
  disabling it is obsolete.

The recipe retains Perl XS and external Perl module dependencies.
Its PLIST follows the 7.3 Automake install destinations: Perl example
converters still install below `Texinfo/Convert`, XS modules move into
`lib/texi2any/XS_extension`, and C libraries into `lib/texi2any/lib`.
The enabled XS/C build also installs new reader, tree-element, configuration
and Texinfo conversion modules, `libtexinfo-main`, and `load_txi_modules`.
Native staging also verified the split `share/texinfo/htmlxref.d` data and
the Unix `info-hooks` script/data replacing the former `htmlxref.cnf` entry.
Native staging and pkgsrc `check-files` must confirm the complete payload.
Patch checksums use pkgsrc's RCS-ID filtering; the source regression invokes
pkgsrc's own checksum verifier and rejects a deliberately unfiltered digest.
Do not weaken pkgsrc's Perl ABI constraints or vendor another Perl runtime
to get through configuration. The pinned Perl 5.44.0 recipe supplies the
required ABI; replacing an installed older Perl requires rollback packages
and a coordinated rebuild of its ABI-bound Perl modules. Test XS loading,
Info/HTML generation, and package file lists before accepting Texinfo.

## Test harness and bootstrap boundaries

GNU make 4.4.1 and DejaGNU 1.6.3 remain upstream current releases. GNU sed
4.10 is supplied by the pinned recipe. Tcl 8.6.18 is the latest supported
8.6 release in 2026, with development ending in 2026 according to
<https://www.tcl-lang.org/software/tcltk/8.6.html>.
The profile updates Expect from 5.45.0 to the last stable 5.45.4;
the [official site](https://core.tcl-lang.org/expect/home) publishes its
archive SHA256. The three pkgsrc portability patches are retained with
refreshed contexts, including the generated configure substitution for
`SHLIB_VERSION`. Library names follow 5.45.4's undotted `5454` suffix.

The official site points to the maintained
[Tcl 9 port](https://github.com/tcltk-depot/expect). Its README identifies
6.0a0 as work in progress, not production ready, with only Linux tested.
Thus this test harness uses the supported Tcl 8.6.18 branch, rather than
an alpha Expect dependency. No other Tcl runtime is installed alongside it.
Remove this exception when a stable Expect supporting Tcl 9 passes the
NetBSD PTY/spawn tests and DejaGNU/GCC test driver checks. This is a bounded
compiler-test dependency, not the release development-runtime selection.

These recipe adaptations and archive checks are source preparation only.
They are not evidence of a passed native GCC build or complete test suite.
