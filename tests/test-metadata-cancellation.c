#include "thunar/thunar-gio-extensions.h"
#include "thunar/thunar-io-jobs.h"
#include "thunar/thunar-simple-job.h"
#include "thunar/thunar-util.h"

typedef struct
{
  GObject  parent;
  gboolean is_symlink;
} TestFile;

typedef GObjectClass TestFileClass;

static guint         query_count;
static guint         cancel_at_query;
static GCancellable *expected_cancellable;

static GType
test_file_get_type (void);

static GFileInfo *
test_file_query_info (GFile              *file,
                      const gchar        *attributes,
                      GFileQueryInfoFlags flags,
                      GCancellable       *cancellable,
                      GError            **error)
{
  GFileInfo *info = g_file_info_new ();

  /* Cancellation must stop further I/O, regardless of how many queries ran. */
  g_assert_false (g_cancellable_is_cancelled (cancellable));

  if (expected_cancellable != NULL)
    g_assert_true (cancellable == expected_cancellable);

  query_count++;
  g_file_info_set_file_type (info, G_FILE_TYPE_REGULAR);
  g_file_info_set_size (info, 10);
  g_file_info_set_content_type (info, "text/plain");
  if (((TestFile *) file)->is_symlink)
    {
      g_file_info_set_is_symlink (info, TRUE);
      g_file_info_set_symlink_target (info, "target");
    }
  if (query_count == cancel_at_query)
    g_cancellable_cancel (cancellable);

  return info;
}

static gchar *
test_file_get_uri (GFile *file)
{
  return g_strdup_printf ("test:///%p", (void *) file);
}

static GFile *
test_file_get_parent (GFile *file)
{
  return g_object_new (test_file_get_type (), NULL);
}

static GFile *
test_file_resolve_relative_path (GFile       *file,
                                 const gchar *relative_path)
{
  return g_object_new (test_file_get_type (), NULL);
}

static void
test_file_iface_init (GFileIface *iface)
{
  iface->query_info = test_file_query_info;
  iface->get_uri = test_file_get_uri;
  iface->get_parent = test_file_get_parent;
  iface->resolve_relative_path = test_file_resolve_relative_path;
}

G_DEFINE_TYPE_WITH_CODE (TestFile, test_file, G_TYPE_OBJECT,
                         G_IMPLEMENT_INTERFACE (G_TYPE_FILE, test_file_iface_init))

static void
test_file_class_init (TestFileClass *klass)
{
}

static void
test_file_init (TestFile *file)
{
}

static void
test_statusbar_cancellation (void)
{
  g_autoptr (GCancellable) cancellable = g_cancellable_new ();
  g_autoptr (GHashTable) files = g_hash_table_new_full (g_direct_hash, NULL, g_object_unref, NULL);
  gchar *text;

  for (guint i = 0; i < 3; i++)
    g_hash_table_add (files, g_object_new (test_file_get_type (), NULL));

  query_count = 0;
  cancel_at_query = 0;
  text = thunar_util_get_statusbar_text_for_files (files, FALSE, FALSE,
                                                   THUNAR_DATE_STYLE_SIMPLE, NULL, 0, cancellable);
  g_assert_nonnull (text);
  g_free (text);

  query_count = 0;
  cancel_at_query = 1;
  text = thunar_util_get_statusbar_text_for_files (files, FALSE, FALSE,
                                                   THUNAR_DATE_STYLE_SIMPLE, NULL, 0, cancellable);
  g_assert_null (text);

  query_count = 0;
  text = thunar_util_get_statusbar_text_for_files (files, FALSE, FALSE,
                                                   THUNAR_DATE_STYLE_SIMPLE, NULL, 0, cancellable);
  g_assert_null (text);
}

static void
test_content_type_cancellation (void)
{
  g_autoptr (GHashTable) files = g_hash_table_new (g_direct_hash, NULL);
  g_autoptr (GError) error = NULL;
  ThunarJob  *job = thunar_io_jobs_load_content_types (files);
  GArray     *params = thunar_simple_job_get_param_values (THUNAR_SIMPLE_JOB (job));
  GHashTable *pending = g_value_get_boxed (&g_array_index (params, GValue, 0));

  for (guint i = 0; i < 3; i++)
    g_hash_table_insert (pending, g_object_new (test_file_get_type (), NULL), NULL);

  query_count = 0;
  cancel_at_query = 1;
  g_assert_false (THUNAR_JOB_GET_CLASS (job)->execute (job, &error));
  g_assert_error (error, G_IO_ERROR, G_IO_ERROR_CANCELLED);

  /* Cancelled completion must not try to load or update any ThunarFile. */
  g_signal_emit_by_name (job, "finished");
  g_object_unref (job);
}

static void
test_content_type_query (void)
{
  g_autoptr (GFile) file = g_object_new (test_file_get_type (), NULL);
  g_autofree gchar *content_type = NULL;

  query_count = 0;
  cancel_at_query = 0;
  content_type = thunar_g_file_get_content_type (file, NULL);
  g_assert_cmpstr (content_type, ==, "text/plain");
}

static void
test_content_type_symlink (gconstpointer data)
{
  g_autoptr (GFile) file = g_object_new (test_file_get_type (), NULL);
  g_autoptr (GCancellable) cancellable = g_cancellable_new ();
  g_autofree gchar *content_type = NULL;

  ((TestFile *) file)->is_symlink = TRUE;
  query_count = 0;
  cancel_at_query = GPOINTER_TO_UINT (data);
  expected_cancellable = cancellable;

  /* Resolve a relative link, including its parent and target. Cancellation may
   * race with a successful query, so the fake backend still returns its info. */
  content_type = thunar_g_file_get_content_type (file, cancellable);
  if (cancel_at_query == 0)
    g_assert_cmpstr (content_type, ==, "text/plain");
  else
    g_assert_null (content_type);

  expected_cancellable = NULL;
}

int
main (int argc, char **argv)
{
  g_test_init (&argc, &argv, NULL);
  g_test_add_func ("/metadata/statusbar-cancellation", test_statusbar_cancellation);
  g_test_add_func ("/metadata/content-type-cancellation", test_content_type_cancellation);
  g_test_add_func ("/metadata/content-type-query", test_content_type_query);
  g_test_add_data_func ("/metadata/content-type-symlink-query", GUINT_TO_POINTER (0), test_content_type_symlink);
  g_test_add_data_func ("/metadata/content-type-symlink-cancellation", GUINT_TO_POINTER (2), test_content_type_symlink);
  g_test_add_data_func ("/metadata/content-type-symlink-parent-cancellation", GUINT_TO_POINTER (3), test_content_type_symlink);
  g_test_add_data_func ("/metadata/content-type-symlink-target-cancellation", GUINT_TO_POINTER (4), test_content_type_symlink);
  return g_test_run ();
}
