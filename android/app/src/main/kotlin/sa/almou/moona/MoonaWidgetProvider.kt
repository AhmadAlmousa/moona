package sa.almou.moona

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject

/**
 * Renders the Moona list on the home screen from the snapshot the Flutter app
 * writes (lib/features/widget/widget_bridge.dart). Item rows come from
 * [MoonaWidgetService]; the "+" launches the app to the add sheet, while the
 * detail toggle and per-row check-offs run in the background Dart isolate.
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
        val rtl = payload?.optBoolean("rtl", false) ?: false

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

            // Detail toggle runs in the background isolate (no app launch).
            views.setOnClickPendingIntent(
                R.id.widget_detail_toggle,
                fixedBackground(context, Uri.parse("moona://toggledetail"), id),
            )

            // Scrollable list, its empty view, and the per-row tap template.
            val adapter = Intent(context, MoonaWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_list, adapter)
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)
            views.setPendingIntentTemplate(R.id.widget_list, rowTemplate(context))

            appWidgetManager.updateAppWidget(id, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(id, R.id.widget_list)
        }
    }

    /** Immutable broadcast for a fixed-URI action (e.g. the detail toggle). */
    private fun fixedBackground(context: Context, uri: Uri, requestCode: Int): PendingIntent {
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

    /**
     * Mutable template the list fills with each row's data URI
     * (`moona://scratch?id=…` / `moona://undo?id=…`). The package's
     * HomeWidgetBackgroundIntent is immutable, so it can't serve as a template.
     */
    private fun rowTemplate(context: Context): PendingIntent {
        val intent = Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
            action = ACTION_BACKGROUND
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            flags = flags or PendingIntent.FLAG_MUTABLE
        }
        return PendingIntent.getBroadcast(context, TEMPLATE_REQUEST, intent, flags)
    }

    companion object {
        const val KEY_PAYLOAD = "moona_widget_payload"
        const val ACTION_BACKGROUND = "es.antonborri.home_widget.action.BACKGROUND"
        private const val TEMPLATE_REQUEST = 100

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
