package com.pbrockt.family_planner

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Trennzeichen zwischen Farb-Hex und Text einer Termin-Zeile (siehe home_widgets.dart). */
private const val COLOR_SEP = '\u001F'

/** Klartext: evtl. Farb-Markierung am Zeilenanfang entfernen, Termin → Aufzählungspunkt. */
private fun plainBody(raw: String): String =
    raw.split("\n").joinToString("\n") {
        val s = it.indexOf(COLOR_SEP)
        if (s >= 0) "•  " + it.substring(s + 1) else it
    }

/**
 * „Anstehende Termine"-Widget: schlichte, robuste Textanzeige auf einer weißen
 * Karte. Liest die von Flutter gesetzten Daten und öffnet beim Antippen den
 * Kalender. Bewusst ohne formatierten Text/Bilder gehalten, damit es zuverlässig
 * rendert.
 */
class UpcomingWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val body = plainBody(widgetData.getString("upcoming_body", "–") ?: "–")
        val pending = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("familyplanner://calendar"),
        )
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.fp_widget_upcoming)
            views.setTextViewText(R.id.fp_widget_body, body)
            views.setOnClickPendingIntent(R.id.fp_widget_root, pending)
            try {
                appWidgetManager.updateAppWidget(id, views)
            } catch (e: Throwable) {
                // lieber keine Aktualisierung als ein Absturz
            }
        }
    }
}
