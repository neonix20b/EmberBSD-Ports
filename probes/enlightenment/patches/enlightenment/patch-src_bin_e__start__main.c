Propagate the window manager's final normal/explicit-error exit status.
The launcher otherwise returns its initial -1 after a successful logout.
An exec failure must be a terminal error, not a successful logout or restart loop.
Local EmberBSD change; AI-assisted, not submitted upstream.

--- src/bin/e_start_main.c.orig
+++ src/bin/e_start_main.c
@@ -380,9 +380,9 @@
    _e_start_stdout_err_redir(home);
    if (trace) _e_ptrace_traceme(really_know);
    execv(args[0], args);
-   // We failed, 0 means normal exit from E with no restart or crash so
-   // let's exit
-   return 0;
+   perror(args[0]);
+   /* 101 is a terminal error; other nonzero statuses request a restart. */
+   return 101;
 }
 
 static Eina_Bool
@@ -831,11 +831,13 @@
              else if (WEXITSTATUS(status) == 101)
                {
                   printf("Explicit error exit from enlightenment\n");
+                  ret = WEXITSTATUS(status);
                   restart = EINA_FALSE;
                   done = EINA_TRUE;
                }
              else if (WEXITSTATUS(status) == 0)
                {
+                  ret = WEXITSTATUS(status);
                   restart = EINA_FALSE;
                   done = EINA_TRUE;
                }
