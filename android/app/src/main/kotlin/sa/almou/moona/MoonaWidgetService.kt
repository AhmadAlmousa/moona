package sa.almou.moona

import android.content.Context
import android.content.Intent
import android.graphics.Paint
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

/** Supplies the scrollable item rows for [MoonaWidgetProvider]. */
class MoonaWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        MoonaWidgetFactory(applicationContext)
}

private class MoonaWidgetFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {

    private var items = JSONArray()
    private var detail = false
    private var rtl = false
    private var undo = ""

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val prefs = HomeWidgetPlugin.getData(context)
        val payload = MoonaWidgetProvider.parsePayload(
            prefs.getString(MoonaWidgetProvider.KEY_PAYLOAD, null),
        )
        items = payload?.optJSONArray("items") ?: JSONArray()
        rtl = payload?.optBoolean("rtl", false) ?: false
        undo = payload?.optJSONObject("strings")?.optString("undo") ?: ""
        detail = prefs.getBoolean(KEY_DETAIL, false)
    }

    override fun onDestroy() {
        items = JSONArray()
    }

    override fun getCount(): Int = items.length()
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false
    override fun getLoadingView(): RemoteViews? = null

    override fun getViewAt(position: Int): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.moona_widget_row)
        val item = items.optJSONObject(position) ?: return row

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
        row.setTextColor(R.id.widget_row_name, color(nameColor))

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
        row.setOnClickFillInIntent(
            R.id.widget_row_root,
            Intent().apply { data = Uri.parse("moona://$action?id=" + Uri.encode(id)) },
        )
        return row
    }

    /** System-theme-aware colour lookup (night values resolve automatically). */
    private fun color(res: Int): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            context.getColor(res)
        } else {
            @Suppress("DEPRECATION")
            context.resources.getColor(res)
        }

    companion object {
        const val KEY_DETAIL = "moona_widget_detail"
    }
}
