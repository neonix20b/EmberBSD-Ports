# Current compiler prerequisites

The GCC profile updates two recipes from the pinned pkgsrc base using
`patches/current-prerequisites.patch`. This is an AI-assisted EmberBSD delta,
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
Its use for the existing Expect/DejaGNU recipe is a bounded test-harness
compatibility question, not permission to install parallel Tcl versions.
Before installation, verify the actual Expect compatibility requirement
and record the removal/update gate if 8.6 must be retained.

These recipe adaptations and archive checks are source preparation only.
They are not evidence of a passed native GCC build or complete test suite.
