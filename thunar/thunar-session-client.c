/* vi:set et ai sw=2 sts=2 ts=2: */
/*-
 * Copyright (c) 2006 Benedikt Meurer <benny@xfce.org>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation; either version 2 of the License, or (at your option)
 * any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program; if not, write to the Free Software Foundation, Inc., 59 Temple
 * Place, Suite 330, Boston, MA  02111-1307  USA
 */

#ifdef HAVE_MEMORY_H
#include <memory.h>
#endif
#include <stdio.h>
#ifdef HAVE_STDLIB_H
#include <stdlib.h>
#endif
#ifdef HAVE_STRING_H
#include <string.h>
#endif

#ifdef ENABLE_SESSION_MANAGEMENT
#include <libxfce4session-client/libxfce4session-client.h>
#endif

#include "thunar/thunar-application.h"
#include "thunar/thunar-file.h"
#include "thunar/thunar-private.h"
#include "thunar/thunar-session-client.h"

#include <glib/gstdio.h>



static void
thunar_session_client_finalize (GObject *object);
#ifdef ENABLE_SESSION_MANAGEMENT
static gboolean
thunar_session_client_connect (ThunarSessionClient *session_client,
                               const gchar         *previous_id);
static void
thunar_session_client_restore (ThunarSessionClient *session_client);
static void
thunar_session_client_quit (XfceSessionClient   *client,
                            ThunarSessionClient *session_client);
static void
thunar_session_client_save_state (XfceSessionClient   *client,
                                  ThunarSessionClient *session_client);
#endif /* !ENABLE_SESSION_MANAGEMENT */



struct _ThunarSessionClientClass
{
  GObjectClass __parent__;
};

struct _ThunarSessionClient
{
  GObject __parent__;

  gchar *path;
  gchar *id;

#ifdef ENABLE_SESSION_MANAGEMENT
  XfceSessionClient *client;
  gboolean           discard_on_finalize;
#endif
};



G_DEFINE_TYPE (ThunarSessionClient, thunar_session_client, G_TYPE_OBJECT)



static void
thunar_session_client_class_init (ThunarSessionClientClass *klass)
{
  GObjectClass *gobject_class;

  gobject_class = G_OBJECT_CLASS (klass);
  gobject_class->finalize = thunar_session_client_finalize;
}



static void
thunar_session_client_init (ThunarSessionClient *session_client)
{
#ifdef ENABLE_SESSION_MANAGEMENT
  /* if thunar quits due to a user request, we need to ask the */
  /* compositor/SM to forget the session data. */
  session_client->discard_on_finalize = TRUE;
#endif
}



static void
thunar_session_client_finalize (GObject *object)
{
  ThunarSessionClient *session_client = THUNAR_SESSION_CLIENT (object);

#ifdef ENABLE_SESSION_MANAGEMENT
  /* disconnect from the session manager */
  if (G_LIKELY (session_client->client != NULL))
    {
      if (session_client->discard_on_finalize)
        xfce_session_client_discard (session_client->client);
      g_object_unref (session_client->client);
    }
#endif /* !ENABLE_SESSION_MANAGEMENT */

  /* release internal state */
  g_free (session_client->path);
  g_free (session_client->id);

  (*G_OBJECT_CLASS (thunar_session_client_parent_class)->finalize) (object);
}



#ifdef ENABLE_SESSION_MANAGEMENT
static gboolean
thunar_session_client_connect (ThunarSessionClient *session_client,
                               const gchar         *previous_id)
{
  session_client->client = xfce_session_client_new_full (XFCE_SESSION_CLIENT_RESTART_NORMAL,
                                                         XFCE_SESSION_CLIENT_PRIORITY_DEFAULT,
                                                         previous_id,
                                                         NULL,
                                                         NULL,
                                                         DATADIR "/applications/" PACKAGE_NAME ".desktop");
  g_signal_connect (session_client->client, "save-state", G_CALLBACK (thunar_session_client_save_state), session_client);
  g_signal_connect (session_client->client, "quit", G_CALLBACK (thunar_session_client_quit), session_client);

  if (!xfce_session_client_connect (session_client->client, NULL))
    {
      g_clear_object (&session_client->client);
      return FALSE;
    }

  /* remember the returned client id */
  session_client->id = g_strdup (xfce_session_client_get_client_id (session_client->client));
  const gchar *restart_command[] = {
    "Thunar",
    "--sm-client-id",
    session_client->id,
    "--daemon",
    NULL,
  };
  xfce_session_client_set_restart_command (session_client->client, restart_command);

  session_client->path = g_strdup (xfce_session_client_get_state_file (session_client->client));
  /* verify that we were able to create the path to the file */
  if (G_UNLIKELY (session_client->path == NULL))
    {
      /* disconnect from the session manager */
      g_clear_object (&session_client->client);
      return FALSE;
    }

  /* try to migrate from the old location, if it exists */
  if (!g_file_test (session_client->path, G_FILE_TEST_EXISTS))
    {
      gchar *spec;
      gchar *old_path;

      spec = g_strconcat ("sessions/Thunar-", session_client->id, NULL);
      old_path = xfce_resource_save_location (XFCE_RESOURCE_CACHE, spec, FALSE);
      if (g_file_test (old_path, G_FILE_TEST_IS_REGULAR | G_FILE_TEST_IS_SYMLINK))
        {
          if (rename (old_path, session_client->path) < 0)
            {
              gchar *contents = NULL;
              gsize  length = 0;
              if (g_file_get_contents (old_path, &contents, &length, NULL)
                  && g_file_set_contents (session_client->path, contents, length, NULL))
                {
                  unlink (old_path);
                }
              g_free (contents);
            }
        }

      g_free (spec);
      g_free (old_path);
      ;
    }

  return TRUE;
}



static void
thunar_session_client_window_destroyed (ThunarSessionClient *session_client,
                                        GtkWidget           *window)

{
  _thunar_return_if_fail (THUNAR_IS_SESSION_CLIENT (session_client));

  const gchar *role = gtk_window_get_role (GTK_WINDOW (window));
  if (session_client->client != NULL && role != NULL)
    xfce_session_client_remove_window (session_client->client, role);
}



static void
thunar_session_client_restore (ThunarSessionClient *session_client)
{
  ThunarApplication *application;
  gchar            **uris;
  GtkWidget         *window;
  XfceRc            *rc;
  gchar            **roles;
  guint              n;
  gint               active_tab;

  /* try to open the session file */
  rc = xfce_rc_simple_open (session_client->path, TRUE);
  if (G_UNLIKELY (rc == NULL))
    return;

  /* grab a reference on the application */
  application = thunar_application_get ();

  /* determine all window roles */
  roles = xfce_rc_get_groups (rc);
  for (n = 0; roles[n] != NULL; ++n)
    {
      /* skip the null group */
      if (strcmp (roles[n], "[NULL]") == 0)
        continue;

      /* enter the group */
      xfce_rc_set_group (rc, roles[n]);

      /* determine the URI for the new window */
      uris = xfce_rc_read_list_entry (rc, "URI", ";");
      if (G_UNLIKELY (uris == NULL))
        continue;

      /* active tab */
      active_tab = xfce_rc_read_int_entry (rc, "PAGE", -1);

      /* open the new window */
      window = g_object_new (THUNAR_TYPE_WINDOW, "role", roles[n], NULL);
      if (session_client->client != NULL)
        {
          xfce_session_client_restore_window (session_client->client, GTK_WINDOW (window), roles[n]);
          g_signal_connect_swapped (window, "destroy", G_CALLBACK (thunar_session_client_window_destroyed), session_client);
        }
      thunar_application_take_window (application, GTK_WINDOW (window));
      gtk_widget_show (window);

      /* open tabs */
      if (!thunar_window_set_directories (THUNAR_WINDOW (window), uris, active_tab))
        {
          /* no tabs were opened */
          gtk_widget_destroy (window);
        }
      else
        {
          /* The accel map will be loaded after the first window is created */
          /* For some reason it is important to do so only AFTER creation of the window! */
          /* When loaded, the accelerators of the first window need to be reconnected */
          if (thunar_application_accel_map_init (application))
            thunar_window_reconnect_accelerators (THUNAR_WINDOW (window));
        }

      /* cleanup */
      g_strfreev (uris);
    }

  /* cleanup */
  g_object_unref (G_OBJECT (application));
  xfce_rc_close (rc);
  g_strfreev (roles);
}



static void
thunar_session_client_quit (XfceSessionClient   *client,
                            ThunarSessionClient *session_client)
{
  ThunarApplication *application;

  _thunar_return_if_fail (THUNAR_IS_SESSION_CLIENT (session_client));
  _thunar_return_if_fail (session_client->client == client);

  /* we are only quitting because the session manager is telling us to, */
  /* not because the user is intentionally quitting. */
  session_client->discard_on_finalize = FALSE;

  application = thunar_application_get ();

  GList *windows = thunar_application_get_windows (application);
  if (windows != NULL)
    {
      for (GList *lp = windows; lp != NULL; lp = lp->next)
        {
          /* ensure xfce_session_client_remove_window() isn't called during shutdown */
          g_signal_handlers_disconnect_by_data (GTK_WINDOW (lp->data), client);
        }

      g_list_free (windows);
    }

  thunar_application_quit (application);
}



static void
thunar_session_client_save_state (XfceSessionClient   *client,
                                  ThunarSessionClient *session_client)
{
  ThunarApplication *application;
  const gchar       *role;
  GList             *uri, *uris; // list of uri strings
  GList             *windows;
  GList             *lp;
  FILE              *fp;
  gint               active_page;

  _thunar_return_if_fail (THUNAR_IS_SESSION_CLIENT (session_client));
  _thunar_return_if_fail (session_client->client == client);

  /* save the active windows */
  application = thunar_application_get ();
  windows = thunar_application_get_windows (application);

  if (windows != NULL)
    {
      /* try to open the session file for writing */
      fp = fopen (session_client->path, "w");
      if (G_LIKELY (fp != NULL))
        {
          for (lp = windows; lp != NULL; lp = lp->next)
            {
              /* determine the role for the window */
              role = gtk_window_get_role (lp->data);
              if (G_UNLIKELY (role == NULL))
                continue;

              /* determine the directories for the window */
              uris = thunar_window_get_directories (lp->data, &active_page);
              if (G_UNLIKELY (uris == NULL))
                continue;

              /* save the window */
              fprintf (fp, "[%s]\n", role);
              fprintf (fp, "PAGE=%d\n", active_page);
              fprintf (fp, "URI=");
              for (uri = uris; uri != NULL; uri = uri->next)
                {
                  gchar *uri_string = uri->data;
                  fprintf (fp, "%s", uri_string);
                  if (G_LIKELY (uri->next != NULL))
                    fprintf (fp, ";");
                }
              fprintf (fp, "\n\n");

              /* cleanup */
              g_list_free_full (uris, g_free);
            }

          /* cleanup */
          fclose (fp);
        }

      g_list_free (windows);
    }
  else
    {
      /* no windows, remove the file */
      g_unlink (session_client->path);
    }

  g_object_unref (G_OBJECT (application));
}
#endif /* !ENABLE_SESSION_MANAGEMENT */



/**
 * thunar_session_client_new:
 * @session_id : the previous session id, or %NULL.
 *
 * Allocates a new #ThunarSessionClient with the specified
 * @session_id. If @session_id is %NULL the session manager
 * will assign a new session id, otherwise the session for
 * the specified id will be restored.
 *
 * Return value: the newly allocated #ThunarSessionClient.
 **/
ThunarSessionClient *
thunar_session_client_new (const gchar *session_id)
{
  ThunarSessionClient *session_client;

  /* allocate a new session client */
  session_client = g_object_new (THUNAR_TYPE_SESSION_CLIENT, NULL);

#ifdef ENABLE_SESSION_MANAGEMENT
  /* try to connect to the session manager and restore the previous session */
  if (thunar_session_client_connect (session_client, session_id) && session_id != NULL)
    thunar_session_client_restore (session_client);
#endif /* !ENABLE_SESSION_MANAGEMENT */

  return session_client;
}



/**
 * thunar_session_client_add_window:
 * @session_client : The #ThunarSessionClient
 * @window : A file manager window
 *
 * Adds @window to the session so the compositor can save and restore its WM
 * state.
 *
 * Only call this on a brand-new window with a brand-new role set.
 **/
void
thunar_session_client_add_window (ThunarSessionClient *session_client,
                                  GtkWindow           *window)
{
  _thunar_return_if_fail (THUNAR_IS_SESSION_CLIENT (session_client));

#ifdef ENABLE_SESSION_MANAGEMENT
  const gchar *role = gtk_window_get_role (window);
  if (session_client->client != NULL && role != NULL)
    {
      xfce_session_client_add_window (session_client->client, window, role);
      g_signal_connect_swapped (window, "destroy", G_CALLBACK (thunar_session_client_window_destroyed), session_client);
    }
#endif /* !ENABLE_SESSION_MANAGEMENT */
}
