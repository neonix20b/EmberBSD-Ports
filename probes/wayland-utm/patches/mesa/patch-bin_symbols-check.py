Origin: EmberBSD; AI-assisted Mesa 26.2.4 test adaptation.
Status: local; not submitted upstream.

Apply the existing ELF bookkeeping-symbol allowlist to NetBSD. Missing API
symbols and unrelated extra exports still fail the upstream check.

--- bin/symbols-check.py.orig
+++ bin/symbols-check.py
@@ -91,7 +91,7 @@
         if len(fields) >= 2 and fields[1] == 'U':
             continue
         symbol_name = fields[0]
-        if platform_name == 'Linux' or platform_name == 'GNU' or platform_name.startswith('GNU/'):
+        if platform_name in ('Linux', 'NetBSD') or platform_name == 'GNU' or platform_name.startswith('GNU/'):
             if symbol_name.split('@')[0] in PLATFORM_SYMBOLS:
                 continue
         elif platform_name == 'Darwin':
