import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'calendar_event.dart';

/// Ein zeitgebundener Termin mit berechneter Position (Minuten ab Tagesbeginn)
/// und Spalten-Layout für überlappende Termine.
class PositionedDayEvent {
  const PositionedDayEvent({
    required this.event,
    required this.startMinute,
    required this.endMinute,
    required this.column,
    required this.columns,
  });

  final CalendarEvent event;
  final int startMinute; // 0..1440, auf den Tag geklemmt
  final int endMinute; // > startMinute
  final int column; // 0-basiert
  final int columns; // Spaltenanzahl der Überlappungsgruppe
}

class _Span {
  _Span(this.event, this.start, this.end);
  final CalendarEvent event;
  final int start;
  final int end;
}

/// Berechnet Minuten-Position und Spalten-Layout der **zeitgebundenen** Termine
/// eines Tages. Überlappende Termine teilen sich die Breite (Greedy-Spalten).
/// Über Mitternacht laufende Termine werden auf den Tag geklemmt.
List<PositionedDayEvent> layoutDayEvents(
    List<CalendarEvent> events, DateTime day) {
  final dayStart = DateTime(day.year, day.month, day.day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  final items = <_Span>[];
  for (final e in events) {
    if (e.allDay || e.isMultiDay) continue;
    final end = e.end ?? e.start.add(const Duration(hours: 1));
    final s = e.start.isBefore(dayStart) ? dayStart : e.start;
    final en = end.isAfter(dayEnd) ? dayEnd : end;
    var sm = s.difference(dayStart).inMinutes;
    var em = en.difference(dayStart).inMinutes;
    if (sm < 0) sm = 0;
    if (em > 1440) em = 1440;
    if (em <= sm) em = math.min(sm + 30, 1440); // Mindestlänge
    items.add(_Span(e, sm, em));
  }
  items.sort((a, b) =>
      a.start != b.start ? a.start.compareTo(b.start) : a.end.compareTo(b.end));

  final result = <PositionedDayEvent>[];
  var i = 0;
  while (i < items.length) {
    // Überlappungsgruppe sammeln.
    var groupEnd = items[i].end;
    final group = <_Span>[items[i]];
    var j = i + 1;
    while (j < items.length && items[j].start < groupEnd) {
      groupEnd = math.max(groupEnd, items[j].end);
      group.add(items[j]);
      j++;
    }
    // Spalten greedy zuweisen.
    final colEnds = <int>[];
    final colOf = <_Span, int>{};
    for (final s in group) {
      var placed = false;
      for (var c = 0; c < colEnds.length; c++) {
        if (s.start >= colEnds[c]) {
          colEnds[c] = s.end;
          colOf[s] = c;
          placed = true;
          break;
        }
      }
      if (!placed) {
        colOf[s] = colEnds.length;
        colEnds.add(s.end);
      }
    }
    for (final s in group) {
      result.add(PositionedDayEvent(
        event: s.event,
        startMinute: s.start,
        endMinute: s.end,
        column: colOf[s]!,
        columns: colEnds.length,
      ));
    }
    i = j;
  }
  return result;
}

/// Tages-Zeitleiste: Stundenraster 0–24 Uhr mit Terminen als Blöcken.
class DayTimeline extends StatefulWidget {
  const DayTimeline({
    super.key,
    required this.day,
    required this.events,
    required this.onTapEvent,
    required this.onCreateAt,
    this.focusTime,
  });

  final DateTime day;
  final List<CalendarEvent> events;
  final void Function(CalendarEvent event) onTapEvent;
  final void Function(DateTime start) onCreateAt;

  /// Optionale Uhrzeit, auf die beim Öffnen gescrollt werden soll (z.B. die
  /// Startzeit eines angetippten Termins). Sonst: aktuelle Stunde (heute) / 8 Uhr.
  final DateTime? focusTime;

  @override
  State<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<DayTimeline> {
  static const double _hourHeight = 56;
  static const double _gutter = 52;

  late final ScrollController _scroll;

  bool get _isToday {
    final now = DateTime.now();
    return now.year == widget.day.year &&
        now.month == widget.day.month &&
        now.day == widget.day.day;
  }

  @override
  void initState() {
    super.initState();
    final focusHour = widget.focusTime?.hour ?? (_isToday ? DateTime.now().hour : 8);
    _scroll = ScrollController(
      initialScrollOffset: ((focusHour - 1).clamp(0, 23)) * _hourHeight,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDay =
        widget.events.where((e) => e.allDay || e.isMultiDay).toList();
    final positioned = layoutDayEvents(widget.events, widget.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allDay.isNotEmpty) _allDayRow(theme, allDay),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: _hourHeight * 24,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final gridWidth = constraints.maxWidth - _gutter - 8;
                  return Stack(
                    children: [
                      ..._hourRows(theme),
                      // Tap-Ebene zum Anlegen (unter den Terminen).
                      Positioned.fill(
                        left: _gutter,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapUp: (d) {
                            final hour = (d.localPosition.dy / _hourHeight)
                                .floor()
                                .clamp(0, 23);
                            widget.onCreateAt(DateTime(widget.day.year,
                                widget.day.month, widget.day.day, hour));
                          },
                        ),
                      ),
                      for (final p in positioned)
                        _eventBlock(theme, p, gridWidth),
                      if (_isToday) _nowLine(theme),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _allDayRow(ThemeData theme, List<CalendarEvent> events) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: theme.dividerColor.withValues(alpha: .5))),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in events)
            ActionChip(
              avatar: CircleAvatar(
                  backgroundColor: e.color ?? theme.colorScheme.primary,
                  radius: 6),
              label: Text(e.summary, overflow: TextOverflow.ellipsis),
              onPressed: () => widget.onTapEvent(e),
            ),
        ],
      ),
    );
  }

  List<Widget> _hourRows(ThemeData theme) {
    final lineColor = theme.dividerColor.withValues(alpha: .4);
    final labelStyle = theme.textTheme.labelSmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return [
      for (var h = 0; h < 24; h++) ...[
        Positioned(
          top: h * _hourHeight,
          left: _gutter,
          right: 0,
          child: Divider(height: 1, thickness: 1, color: lineColor),
        ),
        Positioned(
          top: h * _hourHeight - 6,
          left: 0,
          width: _gutter - 6,
          child: Text(
            '${h.toString().padLeft(2, '0')}:00',
            textAlign: TextAlign.right,
            style: labelStyle,
          ),
        ),
      ],
    ];
  }

  Widget _eventBlock(
      ThemeData theme, PositionedDayEvent p, double gridWidth) {
    final colWidth = gridWidth / p.columns;
    final left = _gutter + p.column * colWidth;
    final top = p.startMinute / 60 * _hourHeight;
    final height =
        math.max((p.endMinute - p.startMinute) / 60 * _hourHeight, 24.0);
    final color = p.event.color ?? theme.colorScheme.primary;
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black87;

    return Positioned(
      left: left,
      top: top,
      width: math.max(colWidth - 2, 0),
      height: height - 2,
      child: Material(
        color: color.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => widget.onTapEvent(p.event),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.event.summary,
                  maxLines: height > 34 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: onColor, fontWeight: FontWeight.w600),
                ),
                if (height > 40)
                  Text(
                    DateFormat('HH:mm').format(p.event.start),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: onColor.withValues(alpha: .85)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nowLine(ThemeData theme) {
    final now = DateTime.now();
    final top = (now.hour * 60 + now.minute) / 60 * _hourHeight;
    return Positioned(
      top: top - 1,
      left: _gutter - 4,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          ),
          Expanded(child: Container(height: 2, color: Colors.red)),
        ],
      ),
    );
  }
}
