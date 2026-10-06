/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Exercise the actual manager with the Linux backend disabled. */

#include "hks-manager.h"

static void
test_unavailable (void)
{
  g_autoptr (PhoshHksManager) manager = NULL;
  gboolean mic_present = TRUE, camera_present = TRUE;

  g_test_expect_message ("phosh-hks-manager", G_LOG_LEVEL_MESSAGE, "*unavailable*");
  manager = phosh_hks_manager_new ();
  g_test_assert_expected_messages ();

  g_object_get (manager,
                "mic-present", &mic_present,
                "camera-present", &camera_present,
                NULL);
  g_assert_false (mic_present);
  g_assert_false (camera_present);
}

int
main (int argc, char **argv)
{
  g_test_init (&argc, &argv, NULL);
  g_test_add_func ("/hks/unavailable", test_unavailable);
  return g_test_run ();
}
