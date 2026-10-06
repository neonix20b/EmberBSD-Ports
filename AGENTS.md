# EmberBSD Ports contributor instructions

This repository owns recipes, portability patches and build probes for
third-party software on EmberBSD. Read the root README and the relevant
probe or recipe documentation before making changes.

- Write code, comments, documentation and commit messages in English.
- Inspect the branch, remotes and existing changes before editing. Use
  normal pulls and pushes on the configured branch; never overwrite
  another contributor's work or force-push.
- Download original sources from their upstream locations. Pin the
  version and checksums; verify them before extraction or patching.
- Preserve licenses, copyright notices and upstream identifiers. Record
  where each patch came from and whether it was accepted upstream.
  Do not conceal AI assistance.
- Prefer pkgsrc conventions for installable package recipes. Do not
  introduce a new package manager merely to apply patches.
- Avoid parallel versions of libraries, interpreters and tools for individual
  applications. Choose one current supported dependency version and adapt its
  consumers through these ports. Check upstream updates and compatibility
  patches before adding an older version alongside it. Any exception needs
  a concrete incompatibility, a documented reason and a removal condition.
  Temporary comparison builds must not become permanent dependencies; remove
  unneeded versions after validation. Test affected consumers when updating
  a shared dependency.
- Keep experimental probes separate from validated package recipes.
  Preserve error exit statuses and do not replace missing system
  behavior with silent stubs.
- New project-owned helpers use shell or an appropriate compiled
  language, not Python. Document upstream Python dependencies honestly.
- Select checks that address the change. A successful configuration or
  dependency build does not establish an application's runtime support.
- Keep build products, source archives, full logs, credentials and
  machine-specific addresses out of Git. Use private build directories.
- Installations, session changes and hardware deployment must be within
  the user's task. A source probe should preserve the active desktop.
