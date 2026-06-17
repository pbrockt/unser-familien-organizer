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
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Trennzeichen zwischen Farb-Hex und Text einer Termin-Zeile (siehe home_widgets.dart). */
private const val COLOR_SEP = '\u001F'
private const val FP_BROWN = 0xFF3E322A.toInt()
private const val FP_BROWN_SOFT = 0xFF8C7F73.toInt()

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
                val c = if (line.startsWith("⏳")) FP_BROWN else FP_BROWN_SOFT
                sb.setSpan(ForegroundColorSpan(c), start, sb.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }
        sb
    } catch (e: Exception) {
        raw.split("\n").joinToString("\n") {
            val s = it.indexOf(COLOR_SEP)
            if (s >= 0) it.substring(s + 1) else it
        }
    }
}

/**
 * Basis für alle FamilyPlanner-Home-Screen-Widgets. Zeigt Titel + (mehrzeiligen)
 * Inhalt aus den von Flutter gesetzten Widget-Daten und öffnet beim Antippen
 * den passenden Tab der App.
 */
abstract class FpWidgetProvider : HomeWidgetProvider() {
    abstract val titleKey: String
    abstract val bodyKey: String
    abstract val route: String
    open val defaultTitle: String = "FamilyPlanner"

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.fp_widget)
            views.setTextViewText(
                R.id.fp_widget_title,
                widgetData.getString(titleKey, defaultTitle) ?: defaultTitle,
            )
            views.setTextViewText(
                R.id.fp_widget_body,
                styledBody(widgetData.getString(bodyKey, "–") ?: "–"),
            )
            val pending = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("familyplanner://$route"),
            )
            views.setOnClickPendingIntent(R.id.fp_widget_root, pending)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

/**
 * „Überblick"-Widget: eigenes Layout mit live tickender Uhrzeit/Datum (TextClock),
 * Wetter-Symbol und einem Textblock „Heute / Morgen / Countdown".
 */
class OverviewWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.fp_widget_overview)
            views.setTextViewText(
                R.id.fp_widget_body,
                styledBody(widgetData.getString("overview_body", "–") ?: "–"),
            )
            val weather = widgetData.getString("overview_weather", "") ?: ""
            views.setTextViewText(R.id.fp_widget_weather, weather)
            views.setViewVisibility(
                R.id.fp_widget_weather,
                if (weather.isBlank()) View.GONE else View.VISIBLE,
            )
            val pending = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("familyplanner://home"),
            )
            views.setOnClickPendingIntent(R.id.fp_widget_root, pending)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

class CalendarTodayWidget : FpWidgetProvider() {
    override val titleKey = "cal_today_title"
    override val bodyKey = "cal_today_body"
    override val route = "calendar"
    override val defaultTitle = "Heute"
}

class CalendarTomorrowWidget : FpWidgetProvider() {
    override val titleKey = "cal_2day_title"
    override val bodyKey = "cal_2day_body"
    override val route = "calendar"
    override val defaultTitle = "Heute & Morgen"
}

class CalendarWeekWidget : FpWidgetProvider() {
    override val titleKey = "cal_week_title"
    override val bodyKey = "cal_week_body"
    override val route = "calendar"
    override val defaultTitle = "Diese Woche"
}

class CalendarMonthWidget : FpWidgetProvider() {
    override val titleKey = "cal_month_title"
    override val bodyKey = "cal_month_body"
    override val route = "calendar"
    override val defaultTitle = "Monat"
}

class TasksWidget : FpWidgetProvider() {
    override val titleKey = "tasks_title"
    override val bodyKey = "tasks_body"
    override val route = "tasks"
    override val defaultTitle = "Aufgaben"
}

class ShoppingWidget : FpWidgetProvider() {
    override val titleKey = "shopping_title"
    override val bodyKey = "shopping_body"
    override val route = "shopping"
    override val defaultTitle = "Einkauf"
}
