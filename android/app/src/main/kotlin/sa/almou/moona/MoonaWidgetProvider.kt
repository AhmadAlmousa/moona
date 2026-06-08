package sa.almou.moona

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Paint
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject

/**
 * Renders the Moona list on the home screen from the snapshot the Flutter app
 * writes (lib/features/widget/widget_bridge.dart).
 *
 * Rows are added **directly** as child [RemoteViews] (no RemoteViewsService /
 * ListView): third-party launchers (e.g. Octopi) routinely fail to host a
 * collection adapter, leaving the list empty even though the data is present.
 * Direct child views render on every launcher. The cost is no scrolling, so the
 * list is capped at [MAX_ROWS] (resize the widget taller to see more).
 *
 * "+" launches the add sheet, the open button launches the app, the detail
 * toggle and per-row check-offs run in the background Dart isolate.
 */
class MoonaWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val payload = parsePayload(widgetData.getString(KEY_PAYLOAD, null))
        val strings = payload?.optJSONObject("strings")
        val title = payload?.optString("title").orFallback(context.getString(R.string.widget_label))
        val empty = strings?.optString("empty").orFallback(context.getString(R.string.widget_open_hint))
        val undo = strings?.optString("undo") ?: ""
        val rtl = payload?.optBoolean("rtl", false) ?: false
        val detail = widgetData.getBoolean(KEY_DETAIL, false)
        val items = payload?.optJSONArray("items") ?: JSONArray()

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.moona_widget)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_empty, empty)
            views.setInt(
                R.id.widget_root,
                "setLayoutDirection",
                if (rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR,
            )

            // "+" opens the app to the in-app add/edit sheet.
            views.setOnClickPendingIntent(
                R.id.widget_add,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("moona://add"),
                ),
            )

            // The open-app button just launches Moona to the list.
            views.setOnClickPendingIntent(
                R.id.widget_open,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("moona://open"),
                ),
            )

            // Detail toggle (compact <-> detailed) runs in the background isolate.
            views.setOnClickPendingIntent(
                R.id.widget_detail_toggle,
                background(context, Uri.parse("moona://toggledetail"), id),
            )

            // Render the item rows directly.
            views.removeAllViews(R.id.widget_list_container)
            val count = items.length()
            views.setViewVisibility(
                R.id.widget_empty,
                if (count == 0) View.VISIBLE else View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_list_container,
                if (count == 0) View.GONE else View.VISIBLE,
            )
            val shown = minOf(count, MAX_ROWS)
            for (i in 0 until shown) {
                val item = items.optJSONObject(i) ?: continue
                views.addView(
                    R.id.widget_list_container,
                    buildRow(context, item, detail, rtl, undo),
                )
            }

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /** One item row, mirroring the in-app card (name, optional meta, strike +
     *  Undo when scratched). The whole row taps through to scratch/undo. */
    private fun buildRow(
        context: Context,
        item: JSONObject,
        detail: Boolean,
        rtl: Boolean,
        undo: String,
    ): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.moona_widget_row)
        val id = item.optString("id")
        val important = item.optBoolean("important", false)
        val scratched = item.optBoolean("scratched", false)

        row.setInt(
            R.id.widget_row_root,
            "setLayoutDirection",
            if (rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR,
        )
        row.setTextViewText(R.id.widget_row_name, item.optString("name"))
        row.setViewVisibility(
            R.id.widget_row_dot,
            if (important && !scratched) View.VISIBLE else View.GONE,
        )

        val nameColor = when {
            scratched -> R.color.moona_on_surface_variant
            important -> R.color.moona_error
            else -> R.color.moona_on_surface
        }
        row.setTextColor(R.id.widget_row_name, color(context, nameColor))

        // Strike through a scratched item (keep anti-aliasing).
        val flags = Paint.ANTI_ALIAS_FLAG or
            (if (scratched) Paint.STRIKE_THRU_TEXT_FLAG else 0)
        row.setInt(R.id.widget_row_name, "setPaintFlags", flags)

        // Undo affordance on a scratched row.
        row.setViewVisibility(
            R.id.widget_row_undo,
            if (scratched) View.VISIBLE else View.GONE,
        )
        if (scratched) row.setTextViewText(R.id.widget_row_undo, undo)

        // Meta line (count · brand · store) only in detail mode on active rows.
        val meta = listOf(
            item.optString("count"),
            item.optString("brand"),
            item.optString("store"),
        ).filter { it.isNotBlank() }.joinToString("  ·  ")
        if (detail && !scratched && meta.isNotEmpty()) {
            row.setTextViewText(R.id.widget_row_meta, meta)
            row.setViewVisibility(R.id.widget_row_meta, View.VISIBLE)
        } else {
            row.setViewVisibility(R.id.widget_row_meta, View.GONE)
        }

        // Whole-row tap toggles the check-off; the background isolate handles it.
        val action = if (scratched) "undo" else "scratch"
        val uri = Uri.parse("moona://$action?id=" + Uri.encode(id))
        row.setOnClickPendingIntent(
            R.id.widget_row_root,
            background(context, uri, id.hashCode() and 0x7fffffff),
        )
        return row
    }

    /** Immutable broadcast for a fixed-URI background action (detail toggle and
     *  per-row scratch/undo) routed to the home_widget background isolate. */
    private fun background(context: Context, uri: Uri, requestCode: Int): PendingIntent {
        val intent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
            action = ACTION_BACKGROUND
            data = uri
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }

    /** System-theme-aware colour lookup (night values resolve automatically). */
    private fun color(context: Context, res: Int): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.getColor(res)
        } else {
            @Suppress("DEPRECATION")
            context.resources.getColor(res)
        }

    companion object {
        const val KEY_PAYLOAD = "moona_widget_payload"
        const val KEY_DETAIL = "moona_widget_detail"
        const val ACTION_BACKGROUND = "es.antonborri.home_widget.action.BACKGROUND"

        /** Direct rows don't scroll, so cap them (resize the widget for more). */
        private const val MAX_ROWS = 50

        fun parsePayload(raw: String?): JSONObject? =
            if (raw.isNullOrEmpty()) null
            else try {
                JSONObject(raw)
            } catch (e: Exception) {
                null
            }
    }
}

private fun String?.orFallback(fallback: String): String =
    if (this.isNullOrEmpty()) fallback else this
