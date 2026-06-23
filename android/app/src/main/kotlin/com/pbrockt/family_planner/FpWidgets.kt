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
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/** Trenner Farbe<->Text einer Zeile (siehe home_widgets.dart). Tab! */
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
 * Formatierter Inhalt: Zeilen mit Markierung bekommen einen farbigen [marker]
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
                sb.append("  ")
                val tStart = sb.length
                sb.append(text)
                sb.setSpan(ForegroundColorSpan(FP_BROWN), tStart, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                // Endzeit „–HH:mm" (bis zum Titel-Trenner) grau + kleiner.
                val titleSep = text.indexOf("  ")
                val timeEnd = if (titleSep >= 0) titleSep else text.length
                val dash = text.indexOf('\u2013')
                if (dash in 0 until timeEnd) {
                    sb.setSpan(ForegroundColorSpan(FP_BROWN_SOFT), tStart + dash, tStart + timeEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    sb.setSpan(RelativeSizeSpan(0.8f), tStart + dash, tStart + timeEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
            } else if (line.isNotEmpty() && line == line.uppercase() && line.any { it.isLetter() }) {
                val st = sb.length
                sb.append(line)
                sb.setSpan(StyleSpan(Typeface.BOLD), st, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                sb.setSpan(RelativeSizeSpan(0.8f), st, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                sb.setSpan(ForegroundColorSpan(FP_BROWN_SOFT), st, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
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

/** „Anstehende Termine" – Kalender-Eintrags-Stil (farbiger Balken ▌). */
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
 * Wendet das Design-Layout (Datums-Kopf, vertikaler Strich, Liste rechts,
 * „+" und Sync) an. Drei Klick-Ziele: Karte → Kalender, „+" → neuer Termin,
 * Sync → synchronisieren. Mit Klartext-Fallback.
 */
private fun applyDesign(
    context: Context,
    mgr: AppWidgetManager,
    id: Int,
    raw: String,
    marker: String,
) {
    fun launch(route: String) = HomeWidgetLaunchIntent.getActivity(
        context,
        MainActivity::class.java,
        Uri.parse("familyplanner://$route"),
    )
    fun build(styled: Boolean) =
        RemoteViews(context.packageName, R.layout.fp_widget_design).apply {
            setTextViewText(
                R.id.fp_widget_body,
                if (styled) styledBody(raw, marker) else plainBody(raw, marker),
            )
            setOnClickPendingIntent(R.id.fp_widget_root, launch("calendar"))
            setOnClickPendingIntent(R.id.fp_widget_add, launch("newevent"))
            setOnClickPendingIntent(R.id.fp_widget_sync, launch("sync"))
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

/** „Countdown" – im Design-Stil (Datums-Kopf, Strich, Liste, +/Sync). */
class CountdownWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val raw = widgetData.getString("countdown_body", "–") ?: "–"
        for (id in appWidgetIds) {
            applyDesign(context, appWidgetManager, id, raw, "●")
        }
    }
}

/** „Termine (Design)" – Design-Stil, farbiger Balken ▌. */
class DesignWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val raw = widgetData.getString("next_body", "–") ?: "–"
        for (id in appWidgetIds) {
            applyDesign(context, appWidgetManager, id, raw, "▌")
        }
    }
}

/** „Schnell-Eingabe" – kleiner Knopf, der direkt die Schnell-Eingabe öffnet. */
class QuickAddWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.fp_widget_quickadd)
            views.setOnClickPendingIntent(
                R.id.fp_widget_root,
                HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    Uri.parse("familyplanner://quickadd"),
                ),
            )
            try {
                appWidgetManager.updateAppWidget(id, views)
            } catch (e: Throwable) {
                // lieber keine Aktualisierung als ein Absturz
            }
        }
    }
}

/**
 * Diagnose für den „Widget-Diagnose"-Knopf in den Einstellungen. Liefert harte
 * Fakten: platzierte Widgets, registrierte Provider und gespeicherte Daten.
 */
fun widgetDiagnostics(context: Context): String {
    val sb = StringBuilder()
    val mgr = AppWidgetManager.getInstance(context)

    for (cls in listOf(NextEventsWidget::class.java, CountdownWidget::class.java)) {
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
    for (key in listOf("next_body", "countdown_body")) {
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
