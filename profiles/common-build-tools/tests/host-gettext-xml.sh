#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Origin: EmberBSD (AI-assisted), installed XML translation after direct-link repair.
set -eu
[ "$#" = 2 ] || { echo "Usage: $0 HOST_PREFIX NEW_WORK" >&2; exit 2; }
prefix=$1 work=$2
mkdir "$work"
cat > "$work/probe.metainfo.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>org.emberbsd.Tools</id>
  <name>Build tools</name>
  <summary>Compile applications</summary>
</component>
XML
cat > "$work/fr.po" <<'PO'
msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\n"
"Language: fr\n"

msgid "Build tools"
msgstr "Outils de compilation"

msgid "Compile applications"
msgstr "Compiler des applications"
PO
"$prefix/bin/msgfmt" --xml --template "$work/probe.metainfo.xml" \
    -l fr -o "$work/translated.xml" "$work/fr.po"
grep -q '<name xml:lang="fr">Outils de compilation</name>' "$work/translated.xml"
grep -q '<summary xml:lang="fr">Compiler des applications</summary>' "$work/translated.xml"
echo 'PASS: installed gettext XML parsing, ITS rules and translated application metadata'
