package com.pbrockt.family_planner

import android.appwidget.AppWidgetManager
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
import es.antonborri.home_widget.HomeWidgetProvider

/** Trennzeichen zwischen Farb-Hex und Text einer Termin-Zeile (siehe home_widgets.dart). */
private const val COLOR_SEP = '\u001F'
private const val FP_BROWN = 0xFF3E322A.toInt()
private const val FP_BROWN_SOFT = 0xFF8C7F73.toInt()

/**
 * Wendet die RemoteViews an. Sollte das (z. B. wegen formatiertem Text) je
 * fehlschlagen, wird auf eine schlichte Klartext-Version zurückgefallen, damit
 * das Widget niemals auf dem System-Platzhalter hängen bleibt.
 */
private fun applyWithFallback(
    mgr: AppWidgetManager,
    id: Int,
    build: (styled: Boolean) -> RemoteViews,
) {
    try {
        mgr.updateAppWidget(id, build(true))
    } catch (e: Throwable) {
        try {
            mgr.updateAppWidget(id, build(false))
        } catch (e2: Throwable) {
            // Aufgeben – lieber keine Aktualisierung als ein Absturz.
        }
    }
}

/** Klartext (Markierungen entfernt, farbiger Punkt → einfacher Aufzählungspunkt). */
fun plainBody(raw: String): String =
    raw.split("\n").joinToString("\n") {
        val s = it.indexOf(COLOR_SEP)
        if (s >= 0) "•  " + it.substring(s + 1) else it
    }

/**
 * Wandelt den von Flutter gelieferten Textblock in formatierten Inhalt um:
 * Zeilen mit Farb-Markierung bekommen einen farbigen Punkt (Kalenderfarbe),
 * GROSSGESCHRIEBENE Zeilen werden als fette Überschriften dargestellt.
 * Bei Problemen wird der reine Text (ohne Markierungen) zurückgegeben.
 */
fun styledBody(raw: String): CharSequence {
    return try {
        val sb = SpannableStringBuilder()
        val lines = raw.split("\n")
        for ((i, line) in lines.withIndex()) {
            if (i > 0) sb.append("\n")
            val sep = line.indexOf(COLOR_SEP)
            if (sep >= 0) {
                val color = try {
                    Color.parseColor(line.substring(0, sep).trim())
                } catch (e: Exception) {
                    FP_BROWN
                }
                val text = line.substring(sep + 1)
                val dotStart = sb.length
                sb.append("●")
                sb.setSpan(ForegroundColorSpan(color), dotStart, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                val textStart = sb.length
                sb.append("  ").append(text)
                sb.setSpan(ForegroundColorSpan(FP_BROWN), textStart, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            } else if (line.isNotEmpty() && line == line.uppercase() && line.any { it.isLetter() }) {
                val start = sb.length
                sb.append(line)
                sb.setSpan(StyleSpan(Typeface.BOLD), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                sb.setSpan(ForegroundColorSpan(FP_BROWN), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            } else {
                val start = sb.length
                sb.append(line)
                sb.setSpan(ForegroundColorSpan(FP_BROWN_SOFT), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }
        sb
    } catch (e: Exception) {
        plainBody(raw)
    }
}

/**
 * „Anstehende Termine"-Widget: zeigt die nächsten Termine im App-Stil
 * (weiße Karte, farbige Punkte je Kalender). Liest die von Flutter gesetzten
 * Daten und öffnet beim Antippen den Kalender.
 */
class UpcomingWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val rawBody = widgetData.getString("upcoming_body", "–") ?: "–"
        val pending = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("familyplanner://calendar"),
        )
        for (id in appWidgetIds) {
            applyWithFallback(appWidgetManager, id) { styled ->
                RemoteViews(context.packageName, R.layout.fp_widget_upcoming).apply {
                    setTextViewText(
                        R.id.fp_widget_body,
                        if (styled) styledBody(rawBody) else plainBody(rawBody),
                    )
                    setOnClickPendingIntent(R.id.fp_widget_root, pending)
                }
            }
        }
    }
}
