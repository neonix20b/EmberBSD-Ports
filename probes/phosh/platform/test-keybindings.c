/* SPDX-License-Identifier: GPL-3.0-or-later */

#include "util.h"

#define TEST_SCHEMA "org.example.phosh.test.keybindings"


static void
on_action (GSimpleAction *action, GVariant *parameter, gpointer data)
{
}


static void
test_existing (void)
{
  const char *bindings[] = { "<Super>b", "F10", NULL };
  g_autoptr (GSettings) settings = g_settings_new (TEST_SCHEMA);
  g_autoptr (GArray) actions = g_array_new (FALSE, TRUE, sizeof (GActionEntry));
  g_autoptr (GStrvBuilder) builder = g_strv_builder_new ();
  g_auto (GStrv) names = NULL;

  g_assert_true (g_settings_set_strv (settings, "existing", bindings));
  PHOSH_UTIL_BUILD_KEYBINDING (actions, builder, settings, "existing", on_action);
  names = g_strv_builder_end (builder);

  g_assert_cmpuint (actions->len, ==, 2);
  g_assert_cmpuint (g_strv_length (names), ==, 2);
  for (guint i = 0; i < actions->len; i++) {
    GActionEntry *entry = &g_array_index (actions, GActionEntry, i);

    g_assert_cmpstr (entry->name, ==, bindings[i]);
    g_assert_cmpstr (names[i], ==, bindings[i]);
    g_assert_true (entry->activate == on_action);
  }
}


static void
test_missing (void)
{
  g_autoptr (GSettings) settings = g_settings_new (TEST_SCHEMA);
  g_autoptr (GArray) actions = g_array_new (FALSE, TRUE, sizeof (GActionEntry));
  g_autoptr (GStrvBuilder) builder = g_strv_builder_new ();
  g_auto (GStrv) names = NULL;

  g_test_expect_message (NULL, G_LOG_LEVEL_WARNING,
                        "*Skipping unavailable keybinding " TEST_SCHEMA "::missing*");
  PHOSH_UTIL_BUILD_KEYBINDING (actions, builder, settings, "missing", on_action);
  g_test_assert_expected_messages ();
  g_assert_cmpuint (actions->len, ==, 0);

  /* Skipping one binding must not prevent the next binding's registration. */
  PHOSH_UTIL_BUILD_KEYBINDING (actions, builder, settings, "existing", on_action);
  names = g_strv_builder_end (builder);
  g_assert_cmpuint (actions->len, ==, 2);
  g_assert_cmpuint (g_strv_length (names), ==, 2);
}


static void
test_empty (void)
{
  g_autoptr (GSettings) settings = g_settings_new (TEST_SCHEMA);
  g_autoptr (GArray) actions = g_array_new (FALSE, TRUE, sizeof (GActionEntry));
  g_autoptr (GStrvBuilder) builder = g_strv_builder_new ();
  g_auto (GStrv) names = NULL;

  PHOSH_UTIL_BUILD_KEYBINDING (actions, builder, settings, "empty", on_action);
  names = g_strv_builder_end (builder);
  g_assert_cmpuint (actions->len, ==, 0);
  g_assert_cmpuint (g_strv_length (names), ==, 0);
}


int
main (int argc, char *argv[])
{
  g_test_init (&argc, &argv, NULL);
  g_test_add_func ("/phosh/keybindings/existing", test_existing);
  g_test_add_func ("/phosh/keybindings/missing", test_missing);
  g_test_add_func ("/phosh/keybindings/empty", test_empty);
  return g_test_run ();
}
