package com.pbrockt.family_planner

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Diagnose für den „Widget-Diagnose"-Knopf in den Einstellungen. Liefert harte
 * Fakten: wie viele Widgets platziert sind, ob Provider registriert ist, ob
 * Daten gespeichert wurden und ob das Anwenden der RemoteViews funktioniert.
 */
fun widgetDiagnostics(context: Context): String {
    val sb = StringBuilder()
    val mgr = AppWidgetManager.getInstance(context)
    val component = ComponentName(context, UpcomingWidget::class.java)

    val ids = try {
        mgr.getAppWidgetIds(component)
    } catch (e: Throwable) {
        sb.append("getAppWidgetIds FEHLER: $e\n")
        IntArray(0)
    }
    sb.append("Platzierte Widgets: ${ids.size}\n")
    if (ids.isNotEmpty()) sb.append("IDs: ${ids.joinToString()}\n")

    val providers = try {
        mgr.installedProviders
            .filter { it.provider.packageName == context.packageName }
            .map { it.provider.className.substringAfterLast('.') }
    } catch (e: Throwable) {
        listOf("FEHLER: $e")
    }
    sb.append("Registrierte Provider: $providers\n")

    val body = HomeWidgetPlugin.getData(context).getString("upcoming_body", null)
    if (body == null) {
        sb.append("Daten 'upcoming_body': NULL (nichts gespeichert)\n")
    } else {
        val ctrl = body.count { it.code < 0x20 && it != '\n' }
        sb.append("Daten 'upcoming_body': ${body.length} Zeichen, Steuerzeichen: $ctrl\n")
        sb.append("Vorschau: ${body.take(100).replace("\n", " | ")}\n")
    }

    for (id in ids) {
        try {
            val views = RemoteViews(context.packageName, R.layout.fp_widget_upcoming)
            views.setTextViewText(R.id.fp_widget_body, body ?: "–")
            mgr.updateAppWidget(id, views)
            sb.append("Anwenden id=$id: OK\n")
        } catch (e: Throwable) {
            sb.append("Anwenden id=$id: FEHLER ${e.javaClass.simpleName}: ${e.message}\n")
        }
    }
    return sb.toString()
}

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
