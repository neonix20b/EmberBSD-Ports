Origin: EmberBSD; AI-assisted adaptation of the Mesa 21.3.9 test.
Status: local; not submitted upstream.

Use the existing ELF bookkeeping-symbol allowlist on NetBSD as on Linux.
Missing API symbols and unrelated extra symbols remain errors.

--- bin/symbols-check.py.orig
+++ bin/symbols-check.py
@@ -41,7 +41,7 @@ def get_symbols_nm(nm, lib):
         if len(fields) == 2 or fields[1] == 'U':
             continue
         symbol_name = fields[0]
-        if platform_name == 'Linux':
+        if platform_name in ('Linux', 'NetBSD'):
             if symbol_name in PLATFORM_SYMBOLS:
                 continue
         elif platform_name == 'Darwin':
