package com.pbrockt.family_planner

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

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
                widgetData.getString(bodyKey, "–") ?: "–",
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
                widgetData.getString("overview_body", "–") ?: "–",
            )
            views.setTextViewText(
                R.id.fp_widget_weather,
                widgetData.getString("overview_weather", "") ?: "",
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
