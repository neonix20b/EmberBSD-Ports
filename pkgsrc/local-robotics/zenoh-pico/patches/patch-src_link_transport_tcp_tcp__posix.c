$NetBSD$

Bound POSIX TCP writes using the existing socket timeout on outbound and
accepted connections. DROP only avoids TX-lock waiting, not blocking send.
Local AI-assisted runtime patch; not submitted upstream. Regression: the
Examples robotics/zenoh-ros2/tests/test_tcp_timeout.c filled-buffer test.

--- src/link/transport/tcp/tcp_posix.c.orig
+++ src/link/transport/tcp/tcp_posix.c
@@ -68,7 +68,8 @@
         z_time_t tv;
         tv.tv_sec = (time_t)(tout / (uint32_t)1000);
         tv.tv_usec = (suseconds_t)((tout % (uint32_t)1000) * (uint32_t)1000);
-        if ((ret == _Z_RES_OK) && (setsockopt(sock->_fd, SOL_SOCKET, SO_RCVTIMEO, (char *)&tv, sizeof(tv)) < 0)) {
+        if ((ret == _Z_RES_OK) && ((setsockopt(sock->_fd, SOL_SOCKET, SO_RCVTIMEO, (char *)&tv, sizeof(tv)) < 0) ||
+             (setsockopt(sock->_fd, SOL_SOCKET, SO_SNDTIMEO, (char *)&tv, sizeof(tv)) < 0))) {
             _Z_ERROR_LOG(_Z_ERR_GENERIC);
             ret = _Z_ERR_GENERIC;
         }
@@ -225,7 +226,8 @@
     z_time_t tv;
     tv.tv_sec = Z_CONFIG_SOCKET_TIMEOUT / (uint32_t)1000;
     tv.tv_usec = (Z_CONFIG_SOCKET_TIMEOUT % (uint32_t)1000) * (uint32_t)1000;
-    if (setsockopt(con_socket, SOL_SOCKET, SO_RCVTIMEO, (char *)&tv, sizeof(tv)) < 0) {
+    if ((setsockopt(con_socket, SOL_SOCKET, SO_RCVTIMEO, (char *)&tv, sizeof(tv)) < 0) ||
+        (setsockopt(con_socket, SOL_SOCKET, SO_SNDTIMEO, (char *)&tv, sizeof(tv)) < 0)) {
         close(con_socket);
         _Z_ERROR_RETURN(_Z_ERR_GENERIC);
     }
