package com.pbrockt.family_planner

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/** Trenner Farbe<->Text einer Termin-Zeile (siehe home_widgets.dart). Tab! */
private const val SEP = '\t'
private const val FP_BROWN = 0xFF3E322A.toInt()
private const val FP_BROWN_SOFT = 0xFF8C7F73.toInt()

/** Klartext-Fallback: Markierung entfernen, [marker] (uncoloriert) voranstellen. */
private fun plainBody(raw: String, marker: String): String =
    raw.split("\n").joinToString("\n") {
        val s = it.indexOf(SEP)
        if (s >= 0) "$marker  " + it.substring(s + 1) else it
    }

/**
 * Formatierter Inhalt: Termin-Zeilen bekommen einen farbigen [marker]
 * (Kalenderfarbe), GROSSGESCHRIEBENE Zeilen werden fett. Nur Text-Spans –
 * keine exotischen View-Typen. Bei Problemen → Klartext.
 */
private fun styledBody(raw: String, marker: String): CharSequence {
    return try {
        val sb = SpannableStringBuilder()
        for ((i, line) in raw.split("\n").withIndex()) {
            if (i > 0) sb.append("\n")
            val sep = line.indexOf(SEP)
            if (sep >= 0) {
                val color = try {
                    Color.parseColor(line.substring(0, sep).trim())
                } catch (e: Exception) {
                    FP_BROWN
                }
                val text = line.substring(sep + 1)
                val mStart = sb.length
                sb.append(marker)
                sb.setSpan(ForegroundColorSpan(color), mStart, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                val tStart = sb.length
                sb.append("  ").append(text)
                sb.setSpan(ForegroundColorSpan(FP_BROWN), tStart, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            } else if (line.isNotEmpty() && line == line.uppercase() && line.any { it.isLetter() }) {
                val st = sb.length
                sb.append(line)
                sb.setSpan(StyleSpan(Typeface.BOLD), st, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                sb.setSpan(ForegroundColorSpan(FP_BROWN), st, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            } else {
                val st = sb.length
                sb.append(line)
                sb.setSpan(ForegroundColorSpan(FP_BROWN_SOFT), st, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }
        sb
    } catch (e: Exception) {
        plainBody(raw, marker)
    }
}

/**
 * Wendet die RemoteViews für eine Widget-Instanz an. Erst formatiert
 * (Spannable), bei Fehler Klartext – damit nie ein Platzhalter hängen bleibt.
 */
private fun applyOne(
    context: Context,
    mgr: AppWidgetManager,
    id: Int,
    raw: String,
    layout: Int,
    route: String,
    marker: String,
) {
    val pending = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("familyplanner://$route"),
    )
    fun build(styled: Boolean) =
        RemoteViews(context.packageName, layout).apply {
            setTextViewText(
                R.id.fp_widget_body,
                if (styled) styledBody(raw, marker) else plainBody(raw, marker),
            )
            setOnClickPendingIntent(R.id.fp_widget_root, pending)
        }
    try {
        mgr.updateAppWidget(id, build(true))
    } catch (e: Throwable) {
        try {
            mgr.updateAppWidget(id, build(false))
        } catch (e2: Throwable) {
            // lieber keine Aktualisierung als ein Absturz
        }
    }
}

/** „Anstehende Termine" – Startseiten-Stil (farbiger Punkt ●). */
class UpcomingWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val raw = widgetData.getString("upcoming_body", "–") ?: "–"
        for (id in appWidgetIds) {
            applyOne(context, appWidgetManager, id, raw, R.layout.fp_widget_upcoming, "calendar", "●")
        }
    }
}

/** „Nächste Termine" – Kalender-Eintrags-Stil (farbiger Balken ▌). */
class NextEventsWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val raw = widgetData.getString("next_body", "–") ?: "–"
        for (id in appWidgetIds) {
            applyOne(context, appWidgetManager, id, raw, R.layout.fp_widget_next, "calendar", "▌")
        }
    }
}

/**
 * Diagnose für den „Widget-Diagnose"-Knopf in den Einstellungen. Liefert harte
 * Fakten: platzierte Widgets, registrierte Provider, gespeicherte Daten und ob
 * das Anwenden der RemoteViews funktioniert.
 */
fun widgetDiagnostics(context: Context): String {
    val sb = StringBuilder()
    val mgr = AppWidgetManager.getInstance(context)

    for (cls in listOf(UpcomingWidget::class.java, NextEventsWidget::class.java)) {
        val ids = try {
            mgr.getAppWidgetIds(ComponentName(context, cls))
        } catch (e: Throwable) {
            sb.append("${cls.simpleName} getAppWidgetIds FEHLER: $e\n")
            IntArray(0)
        }
        sb.append("${cls.simpleName}: ${ids.size} platziert ${ids.joinToString(prefix = "[", postfix = "]")}\n")
    }

    val providers = try {
        mgr.installedProviders
            .filter { it.provider.packageName == context.packageName }
            .map { it.provider.className.substringAfterLast('.') }
    } catch (e: Throwable) {
        listOf("FEHLER: $e")
    }
    sb.append("Registrierte Provider: $providers\n")

    val data = HomeWidgetPlugin.getData(context)
    for (key in listOf("upcoming_body", "next_body")) {
        val body = data.getString(key, null)
        if (body == null) {
            sb.append("'$key': NULL\n")
        } else {
            val ctrl = body.count { it.code < 0x20 && it != '\n' && it != '\t' }
            sb.append("'$key': ${body.length} Zeichen, ungültige Steuerzeichen: $ctrl\n")
        }
    }
    return sb.toString()
}
