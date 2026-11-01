/* vi:set et ai sw=2 sts=2 ts=2: */
/*-
 * Copyright (c) 2022 Amrit Borah <elessar1802@gmail.com>
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

#include "thunar/thunar-text-renderer.h"
#include "thunar/thunar-util.h"



enum
{
  PROP_0,
  PROP_HIGHLIGHT_COLOR,
  PROP_ROUNDED_CORNERS,
  PROP_BORDER_RADIUS,
  PROP_BACKGROUND_COLOR_SELECTED,
  PROP_BACKGROUND_COLOR_SELECTED_BACKDROP,
  PROP_HIGHLIGHTING_ENABLED,
  PROP_MAX_LINES,
};



static void
thunar_text_renderer_finalize (GObject *object);
static void
thunar_text_renderer_get_property (GObject    *object,
                                   guint       prop_id,
                                   GValue     *value,
                                   GParamSpec *pspec);
static void
thunar_text_renderer_set_property (GObject      *object,
                                   guint         prop_id,
                                   const GValue *value,
                                   GParamSpec   *pspec);
static void
thunar_text_renderer_render (GtkCellRenderer     *renderer,
                             cairo_t             *cr,
                             GtkWidget           *widget,
                             const GdkRectangle  *background_area,
                             const GdkRectangle  *cell_area,
                             GtkCellRendererState flags);
static void
thunar_text_renderer_get_preferred_height_for_width (GtkCellRenderer *cell,
                                                     GtkWidget       *widget,
                                                     gint             width,
                                                     gint            *minimum_height,
                                                     gint            *natural_height);
static void
thunar_text_renderer_get_preferred_height (GtkCellRenderer *cell,
                                           GtkWidget       *widget,
                                           gint            *minimum_height,
                                           gint            *natural_height);
static void
thunar_text_renderer_get_aligned_area (GtkCellRenderer     *cell,
                                       GtkWidget           *widget,
                                       GtkCellRendererState flags,
                                       const GdkRectangle  *cell_area,
                                       GdkRectangle        *aligned_area);
static void
thunar_text_renderer_get_preferred_width (GtkCellRenderer *cell,
                                          GtkWidget       *widget,
                                          gint            *minimum_width,
                                          gint            *natural_width);
static guint16
thunar_text_renderer_rgba_to_pango_color (gdouble component);
static PangoLayout *
thunar_text_renderer_get_layout (ThunarTextRenderer  *text_renderer,
                                 GtkWidget           *widget,
                                 const GdkRectangle  *cell_area,
                                 GtkCellRendererState flags,
                                 gint                 width);
static void
thunar_text_renderer_get_offsets (ThunarTextRenderer *text_renderer,
                                  GtkWidget          *widget,
                                  const GdkRectangle *cell_area,
                                  PangoLayout        *layout,
                                  gint               *x_offset,
                                  gint               *y_offset,
                                  gint               *width,
                                  gint               *height);



struct _ThunarTextRendererClass
{
  GtkCellRendererTextClass __parent__;

  void (*default_render_function) (GtkCellRenderer     *cell,
                                   cairo_t             *cr,
                                   GtkWidget           *widget,
                                   const GdkRectangle  *background_area,
                                   const GdkRectangle  *cell_area,
                                   GtkCellRendererState flags);
};

struct _ThunarTextRenderer
{
  GtkCellRendererText __parent__;

  gchar   *highlight_color;
  gboolean rounded_corners;
  gint     border_radius;
  GdkRGBA *background_color_selected;
  GdkRGBA *background_color_selected_backdrop;
  gboolean highlighting_enabled;

  /* maximum number of lines to display, -1 means unlimited, 0 means no text at all */
  gint max_lines;
};



G_DEFINE_TYPE (ThunarTextRenderer, thunar_text_renderer, GTK_TYPE_CELL_RENDERER_TEXT);



static void
thunar_text_renderer_class_init (ThunarTextRendererClass *klass)
{
  GObjectClass         *object_class = G_OBJECT_CLASS (klass);
  GtkCellRendererClass *cell_class = GTK_CELL_RENDERER_CLASS (klass);

  object_class->finalize = thunar_text_renderer_finalize;

  object_class->get_property = thunar_text_renderer_get_property;
  object_class->set_property = thunar_text_renderer_set_property;

  klass->default_render_function = cell_class->render;
  cell_class->render = thunar_text_renderer_render;
  cell_class->get_preferred_width = thunar_text_renderer_get_preferred_width;
  cell_class->get_preferred_height_for_width = thunar_text_renderer_get_preferred_height_for_width;
  cell_class->get_preferred_height = thunar_text_renderer_get_preferred_height;
  cell_class->get_aligned_area = thunar_text_renderer_get_aligned_area;

  /**
   * ThunarTextRenderer:highlight-color:
   *
   * The color with which the cell should be highlighted.
   **/
  g_object_class_install_property (object_class,
                                   PROP_HIGHLIGHT_COLOR,
                                   g_param_spec_string ("highlight-color", "highlight-color", "highlight-color",
                                                        NULL,
                                                        G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));



  /**
   * ThunarTextRenderer:rounded-corners:
   *
   * Determines if the cell should be clipped to rounded corners.
   * Useful when highlighting is enabled & a highlight color is set.
   **/
  g_object_class_install_property (object_class,
                                   PROP_ROUNDED_CORNERS,
                                   g_param_spec_boolean ("rounded-corners", "rounded-corners", "rounded-corners",
                                                         FALSE,
                                                         G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));



  /**
   * ThunarTextRenderer:border-radius:
   *
   * The GTK CSS border radius used for file highlighting.
   */
  g_object_class_install_property (object_class,
                                   PROP_BORDER_RADIUS,
                                   g_param_spec_int ("border-radius", "border-radius", "border-radius",
                                                     -1,
                                                     G_MAXINT,
                                                     -1,
                                                     G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));



  /**
   * ThunarTextRenderer:background-color-selected:
   *
   * The GTK CSS background colour for selected files, or %NULL for the fallback.
   */
  g_object_class_install_property (object_class,
                                   PROP_BACKGROUND_COLOR_SELECTED,
                                   g_param_spec_boxed ("background-color-selected", "background-color-selected", "background-color-selected",
                                                       GDK_TYPE_RGBA,
                                                       G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));

  /**
   * ThunarTextRenderer:background-color-selected-backdrop:
   *
   * The GTK CSS background colour for selected files in an inactive window,
   * or %NULL for the fallback.
   */
  g_object_class_install_property (object_class,
                                   PROP_BACKGROUND_COLOR_SELECTED_BACKDROP,
                                   g_param_spec_boxed ("background-color-selected-backdrop", "background-color-selected-backdrop", "background-color-selected-backdrop",
                                                       GDK_TYPE_RGBA,
                                                       G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));



  /**
   * ThunarTextRenderer:highlighting-enabled:
   *
   * Determines if the cell background should be drawn with highlight color.
   **/
  g_object_class_install_property (object_class,
                                   PROP_HIGHLIGHTING_ENABLED,
                                   g_param_spec_boolean ("highlighting-enabled", "highlighting-enabled", "highlighting-enabled",
                                                         FALSE,
                                                         G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));



  /**
   * ThunarTextRenderer:max-lines:
   *
   * The maximum number of lines the text may occupy. Text which does not
   * fit is ellipsized in the middle of the last line, so that e.g. file
   * extensions stay visible. -1 means no limit, 0 means that no text is
   * displayed at all.
   **/
  g_object_class_install_property (object_class,
                                   PROP_MAX_LINES,
                                   g_param_spec_int ("max-lines", "max-lines", "max-lines",
                                                     -1, G_MAXINT, -1,
                                                     G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS | G_PARAM_EXPLICIT_NOTIFY));
}



static void
thunar_text_renderer_init (ThunarTextRenderer *text_renderer)
{
  text_renderer->highlight_color = NULL;
  text_renderer->border_radius = -1;
  text_renderer->max_lines = -1;
}



static void
thunar_text_renderer_finalize (GObject *object)
{
  ThunarTextRenderer *text_renderer = THUNAR_TEXT_RENDERER (object);

  g_free (text_renderer->highlight_color);
  g_clear_pointer (&text_renderer->background_color_selected, gdk_rgba_free);
  g_clear_pointer (&text_renderer->background_color_selected_backdrop, gdk_rgba_free);

  G_OBJECT_CLASS (thunar_text_renderer_parent_class)->finalize (object);
}



static void
thunar_text_renderer_get_property (GObject    *object,
                                   guint       prop_id,
                                   GValue     *value,
                                   GParamSpec *pspec)
{
  ThunarTextRenderer *text_renderer = THUNAR_TEXT_RENDERER (object);

  switch (prop_id)
    {
    case PROP_HIGHLIGHT_COLOR:
      g_value_set_string (value, text_renderer->highlight_color);
      break;

    case PROP_ROUNDED_CORNERS:
      g_value_set_boolean (value, text_renderer->rounded_corners);
      break;

    case PROP_BACKGROUND_COLOR_SELECTED:
      g_value_set_boxed (value, text_renderer->background_color_selected);
      break;

    case PROP_BACKGROUND_COLOR_SELECTED_BACKDROP:
      g_value_set_boxed (value, text_renderer->background_color_selected_backdrop);
      break;

    case PROP_BORDER_RADIUS:
      g_value_set_int (value, text_renderer->border_radius);
      break;

    case PROP_HIGHLIGHTING_ENABLED:
      g_value_set_boolean (value, text_renderer->highlighting_enabled);
      break;

    case PROP_MAX_LINES:
      g_value_set_int (value, text_renderer->max_lines);
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
      break;
    }
}



static void
thunar_text_renderer_set_property (GObject      *object,
                                   guint         prop_id,
                                   const GValue *value,
                                   GParamSpec   *pspec)
{
  ThunarTextRenderer *text_renderer = THUNAR_TEXT_RENDERER (object);

  switch (prop_id)
    {
    case PROP_HIGHLIGHT_COLOR:
      g_free (text_renderer->highlight_color);
      text_renderer->highlight_color = g_value_dup_string (value);
      break;

    case PROP_ROUNDED_CORNERS:
      text_renderer->rounded_corners = g_value_get_boolean (value);
      break;

    case PROP_BACKGROUND_COLOR_SELECTED:
      g_clear_pointer (&text_renderer->background_color_selected, gdk_rgba_free);
      text_renderer->background_color_selected = g_value_dup_boxed (value);
      break;

    case PROP_BACKGROUND_COLOR_SELECTED_BACKDROP:
      g_clear_pointer (&text_renderer->background_color_selected_backdrop, gdk_rgba_free);
      text_renderer->background_color_selected_backdrop = g_value_dup_boxed (value);
      break;

    case PROP_BORDER_RADIUS:
      text_renderer->border_radius = g_value_get_int (value);
      break;

    case PROP_HIGHLIGHTING_ENABLED:
      text_renderer->highlighting_enabled = g_value_get_boolean (value);
      break;

    case PROP_MAX_LINES:
      if (text_renderer->max_lines != g_value_get_int (value))
        {
          text_renderer->max_lines = g_value_get_int (value);
          g_object_notify_by_pspec (object, pspec);
        }
      break;

    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
      break;
    }
}



/**
 * thunar_text_renderer_new:
 *
 * Creates a new #ThunarTextRenderer. Adjust rendering
 * parameters using object properties. Object properties can be
 * set globally with #g_object_set. Also, with #GtkTreeViewColumn,
 * you can bind a property to a value in a #GtkTreeModel.
 *
 * Return value: (transfer full) The newly allocated #ThunarTextRenderer.
 **/
GtkCellRenderer *
thunar_text_renderer_new (void)
{
  return g_object_new (THUNAR_TYPE_TEXT_RENDERER, NULL);
}



static void
thunar_text_renderer_render (GtkCellRenderer     *cell,
                             cairo_t             *cr,
                             GtkWidget           *widget,
                             const GdkRectangle  *background_area,
                             const GdkRectangle  *cell_area,
                             GtkCellRendererState flags)
{
  ThunarTextRenderer *text_renderer = THUNAR_TEXT_RENDERER (cell);
  GtkStyleContext    *context;
  PangoLayout        *layout;
  PangoRectangle      rect;
  GdkRGBA            *background = NULL;
  gboolean            background_set = FALSE;
  gint                x_offset;
  gint                y_offset;
  gint                xpad;
  gint                ypad;

  /* nothing to draw if no text should be displayed */
  if (text_renderer->max_lines == 0)
    return;

  if (text_renderer->highlighting_enabled)
    thunar_util_clip_view_background (cell,
                                      cr,
                                      background_area,
                                      widget,
                                      flags,
                                      text_renderer->border_radius,
                                      text_renderer->background_color_selected,
                                      text_renderer->background_color_selected_backdrop);

  if (text_renderer->max_lines < 0)
    {
      /* we only needed to manipulate the background_area, otherwise everything remains the same.
         Hence, we are simply running the original render function now */
      THUNAR_TEXT_RENDERER_GET_CLASS (text_renderer)->default_render_function (cell, cr, widget, background_area, cell_area, flags);
      return;
    }

  /* this mirrors gtk_cell_renderer_text_render(), but uses a layout limited to max-lines */
  layout = thunar_text_renderer_get_layout (text_renderer, widget, cell_area, flags, -1);
  thunar_text_renderer_get_offsets (text_renderer, widget, cell_area, layout, &x_offset, &y_offset, NULL, NULL);

  g_object_get (G_OBJECT (cell), "background-set", &background_set, "background-rgba", &background, NULL);
  if (background_set && background != NULL && (flags & GTK_CELL_RENDERER_SELECTED) == 0)
    {
      gdk_cairo_rectangle (cr, background_area);
      gdk_cairo_set_source_rgba (cr, background);
      cairo_fill (cr);
    }
  if (background != NULL)
    gdk_rgba_free (background);

  gtk_cell_renderer_get_padding (cell, &xpad, &ypad);

  pango_layout_get_pixel_extents (layout, NULL, &rect);
  x_offset = x_offset - rect.x;

  cairo_save (cr);
  gdk_cairo_rectangle (cr, cell_area);
  cairo_clip (cr);

  context = gtk_widget_get_style_context (widget);
  gtk_render_layout (context, cr,
                     cell_area->x + x_offset + xpad,
                     cell_area->y + y_offset + ypad,
                     layout);

  cairo_restore (cr);

  g_object_unref (layout);
}



static void
thunar_text_renderer_get_preferred_width (GtkCellRenderer *cell,
                                          GtkWidget       *widget,
                                          gint            *minimum_width,
                                          gint            *natural_width)
{
  if (THUNAR_TEXT_RENDERER (cell)->max_lines != 0)
    {
      GTK_CELL_RENDERER_CLASS (thunar_text_renderer_parent_class)->get_preferred_width (cell, widget, minimum_width, natural_width);
      return;
    }

  /* no text is displayed */
  if (minimum_width != NULL)
    *minimum_width = 0;
  if (natural_width != NULL)
    *natural_width = 0;
}



static void
thunar_text_renderer_get_preferred_height_for_width (GtkCellRenderer *cell,
                                                     GtkWidget       *widget,
                                                     gint             width,
                                                     gint            *minimum_height,
                                                     gint            *natural_height)
{
  ThunarTextRenderer *text_renderer = THUNAR_TEXT_RENDERER (cell);
  PangoLayout        *layout;
  gint                text_height;
  gint                xpad;
  gint                ypad;

  if (text_renderer->max_lines < 0)
    {
      GTK_CELL_RENDERER_CLASS (thunar_text_renderer_parent_class)->get_preferred_height_for_width (cell, widget, width, minimum_height, natural_height);
      return;
    }

  /* no text is displayed */
  if (text_renderer->max_lines == 0)
    {
      if (minimum_height != NULL)
        *minimum_height = 0;
      if (natural_height != NULL)
        *natural_height = 0;
      return;
    }

  gtk_cell_renderer_get_padding (cell, &xpad, &ypad);

  layout = thunar_text_renderer_get_layout (text_renderer, widget, NULL, 0, width - xpad * 2);
  pango_layout_get_pixel_size (layout, NULL, &text_height);
  g_object_unref (layout);

  if (minimum_height != NULL)
    *minimum_height = text_height + ypad * 2;
  if (natural_height != NULL)
    *natural_height = text_height + ypad * 2;
}



static void
thunar_text_renderer_get_preferred_height (GtkCellRenderer *cell,
                                           GtkWidget       *widget,
                                           gint            *minimum_height,
                                           gint            *natural_height)
{
  gint min_width;

  if (THUNAR_TEXT_RENDERER (cell)->max_lines < 0)
    {
      GTK_CELL_RENDERER_CLASS (thunar_text_renderer_parent_class)->get_preferred_height (cell, widget, minimum_height, natural_height);
      return;
    }

  /* same as GtkCellRendererText: the height for the minimum width */
  gtk_cell_renderer_get_preferred_width (cell, widget, &min_width, NULL);
  thunar_text_renderer_get_preferred_height_for_width (cell, widget, min_width, minimum_height, natural_height);
}



static void
thunar_text_renderer_get_aligned_area (GtkCellRenderer     *cell,
                                       GtkWidget           *widget,
                                       GtkCellRendererState flags,
                                       const GdkRectangle  *cell_area,
                                       GdkRectangle        *aligned_area)
{
  ThunarTextRenderer *text_renderer = THUNAR_TEXT_RENDERER (cell);
  PangoLayout        *layout;
  gint                x_offset;
  gint                y_offset;

  if (text_renderer->max_lines < 0)
    {
      GTK_CELL_RENDERER_CLASS (thunar_text_renderer_parent_class)->get_aligned_area (cell, widget, flags, cell_area, aligned_area);
      return;
    }

  /* no text is displayed */
  if (text_renderer->max_lines == 0)
    {
      aligned_area->x = cell_area->x;
      aligned_area->y = cell_area->y;
      aligned_area->width = 0;
      aligned_area->height = 0;
      return;
    }

  layout = thunar_text_renderer_get_layout (text_renderer, widget, cell_area, flags, -1);
  thunar_text_renderer_get_offsets (text_renderer, widget, cell_area, layout, &x_offset, &y_offset,
                                    &aligned_area->width, &aligned_area->height);
  g_object_unref (layout);

  aligned_area->x = cell_area->x + x_offset;
  aligned_area->y = cell_area->y + y_offset;
}



/* Creates a layout like the private get_layout() of GtkCellRendererText
 * (gtk/gtkcellrenderertext.c, GTK 3.24) does, but additionally limits it to
 * "max-lines" lines and ellipsizes the rest. That function is not accessible
 * from subclasses, hence this adapted copy.
 * @width is the wrap width in pixels without padding. If it is negative,
 * the width of @cell_area (if any) or the "wrap-width" is used. If no width
 * is known, the text is not wrapped. */
static PangoLayout *
thunar_text_renderer_get_layout (ThunarTextRenderer  *text_renderer,
                                 GtkWidget           *widget,
                                 const GdkRectangle  *cell_area,
                                 GtkCellRendererState flags,
                                 gint                 width)
{
  PangoLayout          *layout;
  PangoAttrList        *attr_list;
  PangoAttrList        *attributes = NULL;
  PangoFontDescription *font_desc = NULL;
  PangoRectangle        rect;
  PangoUnderline        underline = PANGO_UNDERLINE_NONE;
  PangoAlignment        alignment = PANGO_ALIGN_LEFT;
  PangoWrapMode         wrap_mode = PANGO_WRAP_CHAR;
  GdkRGBA              *foreground = NULL;
  gchar                *text = NULL;
  gchar                *language = NULL;
  gboolean              foreground_set = FALSE;
  gboolean              strikethrough_set = FALSE;
  gboolean              strikethrough = FALSE;
  gboolean              underline_set = FALSE;
  gboolean              scale_set = FALSE;
  gboolean              rise_set = FALSE;
  gboolean              language_set = FALSE;
  gboolean              align_set = FALSE;
  gboolean              single_paragraph = FALSE;
  gdouble               scale = 1.0;
  gint                  rise = 0;
  gint                  wrap_width = -1;
  gint                  xpad;

  g_object_get (G_OBJECT (text_renderer),
                "text", &text,
                "attributes", &attributes,
                "font-desc", &font_desc,
                "foreground-set", &foreground_set,
                "foreground-rgba", &foreground,
                "strikethrough-set", &strikethrough_set,
                "strikethrough", &strikethrough,
                "underline-set", &underline_set,
                "underline", &underline,
                "scale-set", &scale_set,
                "scale", &scale,
                "rise-set", &rise_set,
                "rise", &rise,
                "language-set", &language_set,
                "language", &language,
                "align-set", &align_set,
                "alignment", &alignment,
                "single-paragraph-mode", &single_paragraph,
                "wrap-mode", &wrap_mode,
                "wrap-width", &wrap_width,
                NULL);

  layout = gtk_widget_create_pango_layout (widget, text);
  pango_layout_set_single_paragraph_mode (layout, single_paragraph);

  attr_list = (attributes != NULL) ? pango_attr_list_copy (attributes) : pango_attr_list_new ();

  /* options that affect appearance but not size */
  if (cell_area != NULL)
    {
      if (foreground_set && foreground != NULL && (flags & GTK_CELL_RENDERER_SELECTED) == 0)
        {
          pango_attr_list_insert (attr_list, pango_attr_foreground_new (thunar_text_renderer_rgba_to_pango_color (foreground->red),
                                                                        thunar_text_renderer_rgba_to_pango_color (foreground->green),
                                                                        thunar_text_renderer_rgba_to_pango_color (foreground->blue)));
          pango_attr_list_insert (attr_list, pango_attr_foreground_alpha_new (thunar_text_renderer_rgba_to_pango_color (foreground->alpha)));
        }

      if (strikethrough_set)
        pango_attr_list_insert (attr_list, pango_attr_strikethrough_new (strikethrough));
    }

  if (font_desc != NULL)
    pango_attr_list_insert (attr_list, pango_attr_font_desc_new (font_desc));

  if (scale_set && scale != 1.0)
    pango_attr_list_insert (attr_list, pango_attr_scale_new (scale));

  if (!underline_set)
    underline = PANGO_UNDERLINE_NONE;
  if ((flags & GTK_CELL_RENDERER_PRELIT) == GTK_CELL_RENDERER_PRELIT)
    {
      if (underline == PANGO_UNDERLINE_NONE)
        underline = PANGO_UNDERLINE_SINGLE;
      else if (underline == PANGO_UNDERLINE_SINGLE)
        underline = PANGO_UNDERLINE_DOUBLE;
    }
  if (underline != PANGO_UNDERLINE_NONE)
    pango_attr_list_insert (attr_list, pango_attr_underline_new (underline));

  if (language_set && language != NULL)
    pango_attr_list_insert (attr_list, pango_attr_language_new (pango_language_from_string (language)));

  if (rise_set)
    pango_attr_list_insert (attr_list, pango_attr_rise_new (rise));

  pango_layout_set_attributes (layout, attr_list);
  pango_attr_list_unref (attr_list);

  /* determine the width of the unwrapped text */
  pango_layout_set_ellipsize (layout, PANGO_ELLIPSIZE_NONE);
  pango_layout_get_extents (layout, NULL, &rect);

  /* determine the wrap width */
  if (width < 0)
    {
      gtk_cell_renderer_get_padding (GTK_CELL_RENDERER (text_renderer), &xpad, NULL);
      width = (cell_area != NULL) ? MAX (cell_area->width - xpad * 2, 1) : wrap_width;
    }

  /* wrap the text (if a width is known) */
  if (width >= 0)
    {
      pango_layout_set_width (layout, MIN (MAX (width, 1) * PANGO_SCALE, rect.width));
      pango_layout_set_wrap (layout, wrap_mode);
    }
  else
    {
      pango_layout_set_width (layout, -1);
    }

  /* ellipsize everything beyond "max-lines" lines, in the middle of the last
   * line, in order to keep e.g. file extensions visible (see #1765) */
  pango_layout_set_ellipsize (layout, PANGO_ELLIPSIZE_MIDDLE);
  pango_layout_set_height (layout, -text_renderer->max_lines);

  if (align_set)
    pango_layout_set_alignment (layout, alignment);
  else
    pango_layout_set_alignment (layout, (gtk_widget_get_direction (widget) == GTK_TEXT_DIR_RTL) ? PANGO_ALIGN_RIGHT : PANGO_ALIGN_LEFT);

  if (attributes != NULL)
    pango_attr_list_unref (attributes);
  if (font_desc != NULL)
    pango_font_description_free (font_desc);
  if (foreground != NULL)
    gdk_rgba_free (foreground);
  g_free (language);
  g_free (text);

  return layout;
}



/* mirrors the private get_size() of GtkCellRendererText */
static void
thunar_text_renderer_get_offsets (ThunarTextRenderer *text_renderer,
                                  GtkWidget          *widget,
                                  const GdkRectangle *cell_area,
                                  PangoLayout        *layout,
                                  gint               *x_offset,
                                  gint               *y_offset,
                                  gint               *width,
                                  gint               *height)
{
  PangoRectangle rect;
  gfloat         xalign;
  gfloat         yalign;
  gint           xpad;
  gint           ypad;

  gtk_cell_renderer_get_padding (GTK_CELL_RENDERER (text_renderer), &xpad, &ypad);
  gtk_cell_renderer_get_alignment (GTK_CELL_RENDERER (text_renderer), &xalign, &yalign);

  pango_layout_get_pixel_extents (layout, NULL, &rect);

  rect.height = MIN (rect.height, cell_area->height - 2 * ypad);
  rect.width = MIN (rect.width, cell_area->width - 2 * xpad);

  if (x_offset != NULL)
    {
      if (gtk_widget_get_direction (widget) == GTK_TEXT_DIR_RTL)
        *x_offset = (1.0 - xalign) * (cell_area->width - (rect.width + (2 * xpad)));
      else
        *x_offset = xalign * (cell_area->width - (rect.width + (2 * xpad)));
      *x_offset = MAX (*x_offset, 0);
    }

  if (y_offset != NULL)
    *y_offset = MAX (yalign * (cell_area->height - (rect.height + (2 * ypad))), 0);

  if (width != NULL)
    *width = xpad * 2 + rect.width;

  if (height != NULL)
    *height = ypad * 2 + rect.height;
}



/* converts a GdkRGBA color component (0.0 - 1.0) to a PangoColor component,
 * the same way GtkCellRendererText does */
static guint16
thunar_text_renderer_rgba_to_pango_color (gdouble component)
{
  return CLAMP (component * G_MAXUINT16 + 0.5, 0, G_MAXUINT16);
}
