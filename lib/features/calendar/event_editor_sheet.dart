import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/account_providers.dart';
import '../../core/caldav/caldav_exception.dart';
import '../../shared/utils/hex_color.dart';
import '../../shared/widgets/conflict_dialog.dart';
import '../../shared/widgets/countdown_confirm_dialog.dart';
import 'calendar_event.dart';
import 'event_providers.dart';
import 'event_templates.dart';

/// Öffnet den Termin-Editor zum Anlegen ([existing] == null) oder Bearbeiten.
Future<void> showEventEditor(
  BuildContext context, {
  CalendarEvent? existing,
  DateTime? initialDay,
  DateTime? initialStart,
  String? initialTitle,
  bool initialAllDay = false,
  String? initialCalendarHref,
  DateTime? initialEnd,
  String? initialRrule,
  int? initialReminderMinutes,
  bool initialSaveAsTemplate = false,
  String? initialLocation,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _EventEditorSheet(
        existing: existing,
        initialDay: initialDay,
        initialStart: initialStart,
        initialTitle: initialTitle,
        initialAllDay: initialAllDay,
        initialCalendarHref: initialCalendarHref,
        initialEnd: initialEnd,
        initialRrule: initialRrule,
        initialReminderMinutes: initialReminderMinutes,
        initialSaveAsTemplate: initialSaveAsTemplate,
        initialLocation: initialLocation,
      ),
    ),
  );
}

class _EventEditorSheet extends ConsumerStatefulWidget {
  const _EventEditorSheet({
    this.existing,
    this.initialDay,
    this.initialStart,
    this.initialTitle,
    this.initialAllDay = false,
    this.initialCalendarHref,
    this.initialEnd,
    this.initialRrule,
    this.initialReminderMinutes,
    this.initialSaveAsTemplate = false,
    this.initialLocation,
  });
  final CalendarEvent? existing;
  final DateTime? initialDay;

  /// Vorbelegte Startzeit (Datum + Uhrzeit), z.B. beim Tippen auf eine Stunde
  /// in der Tagesansicht. Hat Vorrang vor [initialDay].
  final DateTime? initialStart;

  /// Vorbelegter Titel (z.B. aus der Schnell-Eingabe).
  final String? initialTitle;

  /// Vorbelegt als Ganztags-Termin (Schnell-Eingabe ohne Uhrzeit).
  final bool initialAllDay;

  /// Vorausgewählter Zielkalender (z.B. aus der Schnell-Eingabe).
  final String? initialCalendarHref;

  /// Vorbelegtes Ende (Schnell-Eingabe „14–16 Uhr" / „für 2 Std").
  final DateTime? initialEnd;

  /// Vorbelegte Wiederholung als RRULE-String (z.B. „FREQ=WEEKLY").
  final String? initialRrule;

  /// Vorbelegte Erinnerung in Minuten.
  final int? initialReminderMinutes;

  /// Vorbelegt: „als Vorlage speichern" angehakt.
  final bool initialSaveAsTemplate;

  /// Vorbelegter Ort.
  final String? initialLocation;

  @override
  ConsumerState<_EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends ConsumerState<_EventEditorSheet> {
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _descCtrl;
  final FocusNode _summaryFocus = FocusNode();

  /// Beim Speichern als Vorlage merken.
  bool _saveAsTemplate = false;

  bool _allDay = false;
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  String? _calendarHref;

  /// Erinnerung in Minuten vor Beginn (`null` = aus). Standard: aus.
  int? _reminderMinutes;

  /// Wiederholung: 'none'/'DAILY'/'WEEKLY'/'BIWEEKLY'/'MONTHLY'/'YEARLY'.
  String _repeat = 'none';

  /// Serien-Ende: 'never' (endlos) / 'until' (bis Datum) / 'count' (Anzahl).
  String _repeatEnd = 'never';
  DateTime? _repeatUntil;
  int _repeatCount = 10;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  /// Übersetzt die Auswahl inkl. Serien-Ende in eine RRULE (ohne Präfix);
  /// `null` = Einzeltermin.
  String? _rruleFor(String r) {
    final base = switch (r) {
      'DAILY' => 'FREQ=DAILY',
      'WEEKLY' => 'FREQ=WEEKLY',
      'BIWEEKLY' => 'FREQ=WEEKLY;INTERVAL=2',
      'MONTHLY' => 'FREQ=MONTHLY',
      'YEARLY' => 'FREQ=YEARLY',
      _ => null,
    };
    if (base == null) return null;
    if (_repeatEnd == 'until' && _repeatUntil != null) {
      return '$base;UNTIL=${_untilValue(_repeatUntil!)}';
    }
    if (_repeatEnd == 'count') {
      return '$base;COUNT=${_repeatCount < 1 ? 1 : _repeatCount}';
    }
    return base;
  }

  /// Rundet eine (z.B. aus der Schnell-Eingabe stammende) Erinnerungs-Minutenzahl
  /// auf einen der Dropdown-Werte, damit die Vorauswahl gültig ist.
  int? _snapReminder(int? minutes) {
    if (minutes == null || minutes <= 0) return null;
    const options = [5, 15, 30, 60, 120, 1440];
    var best = options.first;
    for (final o in options) {
      if ((o - minutes).abs() < (best - minutes).abs()) best = o;
    }
    return best;
  }

  /// UNTIL-Wert: Ganztägig als DATE (YYYYMMDD), sonst DATE-TIME in UTC.
  String _untilValue(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d =
        '${date.year.toString().padLeft(4, '0')}'
        '${two(date.month)}${two(date.day)}';
    return _allDay ? d : '${d}T235959Z';
  }

  /// Liest die Wiederholung aus einem vorhandenen iCal-Text (für die Vorauswahl
  /// beim Bearbeiten).
  String _repeatFromIcal(String raw) {
    final m = RegExp(r'RRULE:([^\r\n]*)').firstMatch(raw);
    if (m == null) return 'none';
    final rule = m.group(1)!.toUpperCase();
    final freq = RegExp(r'FREQ=([A-Z]+)').firstMatch(rule)?.group(1);
    final interval = RegExp(r'INTERVAL=(\d+)').firstMatch(rule)?.group(1);
    return switch (freq) {
      'DAILY' => 'DAILY',
      'WEEKLY' => interval == '2' ? 'BIWEEKLY' : 'WEEKLY',
      'MONTHLY' => 'MONTHLY',
      'YEARLY' => 'YEARLY',
      _ => 'none',
    };
  }

  /// Liest das Serien-Ende (COUNT/UNTIL) aus einem vorhandenen iCal-Text.
  void _repeatEndFromIcal(String raw) {
    final m = RegExp(r'RRULE:([^\r\n]*)').firstMatch(raw);
    if (m == null) return;
    final rule = m.group(1)!.toUpperCase();
    final count = RegExp(r'COUNT=(\d+)').firstMatch(rule)?.group(1);
    final until = RegExp(r'UNTIL=(\d{8})').firstMatch(rule)?.group(1);
    if (count != null) {
      _repeatEnd = 'count';
      _repeatCount = int.tryParse(count) ?? 10;
    } else if (until != null) {
      _repeatEnd = 'until';
      _repeatUntil = DateTime(
        int.parse(until.substring(0, 4)),
        int.parse(until.substring(4, 6)),
        int.parse(until.substring(6, 8)),
      );
    }
  }

  Future<void> _pickRepeatUntil() async {
    final base = _repeatUntil ?? _startDate.add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: _startDate,
      lastDate: DateTime(_startDate.year + 10),
    );
    if (picked != null) setState(() => _repeatUntil = picked);
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _summaryCtrl = TextEditingController(
      text: e?.summary ?? widget.initialTitle ?? '',
    );
    _locationCtrl = TextEditingController(
      text: e?.location ?? widget.initialLocation ?? '',
    );
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _reminderMinutes =
        e?.reminderMinutes ?? _snapReminder(widget.initialReminderMinutes);
    _saveAsTemplate = widget.initialSaveAsTemplate;

    if (e != null) {
      _allDay = e.allDay;
      _repeat = _repeatFromIcal(e.rawIcal);
      _repeatEndFromIcal(e.rawIcal);
      _startDate = DateTime(e.start.year, e.start.month, e.start.day);
      _startTime = TimeOfDay.fromDateTime(e.start);
      final end = e.end ?? e.start.add(const Duration(hours: 1));
      // Bei Ganztags-Terminen ist DTEND exklusiv → letzten Tag anzeigen.
      final shownEnd = e.allDay ? end.subtract(const Duration(days: 1)) : end;
      _endDate = DateTime(shownEnd.year, shownEnd.month, shownEnd.day);
      _endTime = TimeOfDay.fromDateTime(end);
      _calendarHref = e.calendarHref;
    } else if (widget.initialStart != null) {
      // Vorbelegte Startzeit (z.B. Tippen auf eine Stunde in der Tagesansicht
      // oder Schnell-Eingabe).
      _allDay = widget.initialAllDay;
      _calendarHref = widget.initialCalendarHref;
      final start = widget.initialStart!;
      _startDate = DateTime(start.year, start.month, start.day);
      _startTime = TimeOfDay(hour: start.hour, minute: start.minute);
      final iEnd = widget.initialEnd;
      if (iEnd != null) {
        _endDate = DateTime(iEnd.year, iEnd.month, iEnd.day);
        _endTime = TimeOfDay(hour: iEnd.hour, minute: iEnd.minute);
      } else {
        _endDate = _startDate;
        _endTime = TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute);
      }
      final rrule = widget.initialRrule;
      if (rrule != null && rrule.isNotEmpty) {
        _repeat = _repeatFromIcal('RRULE:$rrule');
        _repeatEndFromIcal('RRULE:$rrule');
      }
    } else {
      final base = widget.initialDay ?? DateTime.now();
      final start = DateTime(
        base.year,
        base.month,
        base.day,
        DateTime.now().hour + 1,
        0,
      );
      _startDate = DateTime(start.year, start.month, start.day);
      _startTime = TimeOfDay(hour: start.hour, minute: 0);
      _endDate = _startDate;
      _endTime = TimeOfDay(hour: (start.hour + 1) % 24, minute: 0);
    }
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _locationCtrl.dispose();
    _descCtrl.dispose();
    _summaryFocus.dispose();
    super.dispose();
  }

  /// Übernimmt Felder aus einer gewählten Vorlage (Titel ist bereits gesetzt).
  void _applyTemplate(EventTemplate t) {
    // Kalender nur übernehmen, wenn er (noch) existiert – sonst Dropdown-Assertion.
    final cals = ref.read(collectionsProvider).value ?? const [];
    final href = t.calendarHref;
    final calOk = href != null && cals.any((c) => c.href == href);
    setState(() {
      _locationCtrl.text = t.location ?? '';
      _descCtrl.text = t.description ?? '';
      _allDay = t.allDay;
      if (calOk) _calendarHref = href;
      if (!t.allDay) {
        // Startuhrzeit aus der Vorlage übernehmen (Datum bleibt der gewählte Tag).
        if (t.startMinuteOfDay != null) {
          _startTime = TimeOfDay(
            hour: t.startMinuteOfDay! ~/ 60,
            minute: t.startMinuteOfDay! % 60,
          );
        }
        if (t.durationMinutes != null) {
          final start = _combine(_startDate, _startTime);
          final end = start.add(Duration(minutes: t.durationMinutes!));
          _endDate = DateTime(end.year, end.month, end.day);
          _endTime = TimeOfDay(hour: end.hour, minute: end.minute);
        }
      }
    });
    _summaryFocus.unfocus();
  }

  DateTime _combine(DateTime d, TimeOfDay t) =>
      DateTime(d.year, d.month, d.day, t.hour, t.minute);

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  ({DateTime start, DateTime end})? _resolveTimes() {
    if (_allDay) {
      final start = DateTime(_startDate.year, _startDate.month, _startDate.day);
      // DTEND ist exklusiv → letzter Tag + 1.
      final end = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
      ).add(const Duration(days: 1));
      if (end.isBefore(start)) return null;
      return (start: start, end: end);
    }
    final start = _combine(_startDate, _startTime);
    final end = _combine(_endDate, _endTime);
    if (!end.isAfter(start)) return null;
    return (start: start, end: end);
  }

  Future<void> _save() async {
    final summary = _summaryCtrl.text.trim();
    if (summary.isEmpty) {
      _snack('Bitte einen Titel eingeben.');
      return;
    }
    final times = _resolveTimes();
    if (times == null) {
      _snack('Das Ende muss nach dem Beginn liegen.');
      return;
    }
    final calHref = _calendarHref;
    if (calHref == null || calHref.isEmpty) {
      _snack('Bitte einen Kalender wählen.');
      return;
    }

    final ev = widget.existing;
    final isSeriesInstance =
        ev != null && ev.isRecurring && ev.recurrenceDate != null;

    // Bei Serienterminen fragen: nur diese Instanz oder die ganze Serie?
    var editOnlyThis = false;
    if (isSeriesInstance) {
      final scope = await _askSeriesScope(ev, 'ändern');
      if (scope == null) return;
      editOnlyThis = scope == 'this';
    }
    if (!mounted) return;

    final notifier = ref.read(eventsControllerProvider.notifier);
    final location = _locationCtrl.text.trim();
    final desc = _descCtrl.text.trim();

    Future<bool> write(bool force) async {
      try {
        if (!_isEdit) {
          await notifier.createEvent(
            calendarHref: calHref,
            summary: summary,
            start: times.start,
            end: times.end,
            allDay: _allDay,
            location: location,
            description: desc,
            reminderMinutes: _reminderMinutes,
            rrule: _rruleFor(_repeat),
          );
        } else if (editOnlyThis) {
          await notifier.updateOccurrence(
            ev!,
            summary: summary,
            start: times.start,
            end: times.end,
            allDay: _allDay,
            location: location,
            description: desc,
            force: force,
          );
        } else if (calHref != ev!.calendarHref) {
          // Kalender gewechselt → Termin in die andere Collection verschieben.
          await notifier.moveEvent(
            ev,
            newCalendarHref: calHref,
            summary: summary,
            start: times.start,
            end: times.end,
            allDay: _allDay,
            location: location,
            description: desc,
            reminderMinutes: _reminderMinutes,
            rrule: _rruleFor(_repeat),
            updateRrule: true,
            force: force,
          );
        } else {
          await notifier.updateEvent(
            ev,
            summary: summary,
            start: times.start,
            end: times.end,
            allDay: _allDay,
            location: location,
            description: desc,
            reminderMinutes: _reminderMinutes,
            rrule: _rruleFor(_repeat),
            updateRrule: true,
            force: force,
          );
        }
        return true;
      } on CalDavException catch (e) {
        if (e.isConflict && mounted) {
          final choice = await showConflictDialog(context);
          if (choice == ConflictChoice.keepMine) return write(true);
          if (choice == ConflictChoice.loadServer) {
            ref.invalidate(eventsControllerProvider);
            return true; // eigene Änderung verwerfen, Editor schließen
          }
          return false; // abgebrochen
        }
        if (mounted) _snack('Speichern fehlgeschlagen: $e');
        return false;
      } catch (e) {
        if (mounted) _snack('Speichern fehlgeschlagen: $e');
        return false;
      }
    }

    setState(() => _busy = true);
    final ok = await write(false);
    if (!mounted) return;
    if (ok) {
      if (_saveAsTemplate &&
          (ref.read(templatesEnabledProvider).value ?? true)) {
        final existed =
            (ref.read(eventTemplatesProvider).value ?? const <EventTemplate>[])
                .any((t) => t.summary.toLowerCase() == summary.toLowerCase());
        await ref
            .read(eventTemplatesProvider.notifier)
            .save(
              EventTemplate(
                summary: summary,
                location: location.isEmpty ? null : location,
                description: desc.isEmpty ? null : desc,
                allDay: _allDay,
                startMinuteOfDay: _allDay
                    ? null
                    : times.start.hour * 60 + times.start.minute,
                durationMinutes: _allDay
                    ? null
                    : times.end.difference(times.start).inMinutes,
                calendarHref: calHref,
              ),
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                existed ? 'Vorlage aktualisiert' : 'Vorlage gespeichert',
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  /// Fragt bei Serien-Instanzen klar nach: nur dieser Termin oder ganze Serie.
  /// [verb] ist „ändern" oder „löschen". Rückgabe: 'this', 'series' oder null
  /// (Abbruch).
  Future<String?> _askSeriesScope(CalendarEvent ev, String verb) {
    final dateLabel = DateFormat('EEEE, d. MMMM', 'de_DE').format(ev.start);
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx);
        return SimpleDialog(
          title: Text('Serientermin $verb'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(
                '„${ev.summary}" gehört zu einer Serie. Was möchtest du $verb?',
                style: t.textTheme.bodyMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('Nur dieser Termin'),
              subtitle: Text('Betrifft nur den Termin am $dateLabel.'),
              onTap: () => Navigator.pop(ctx, 'this'),
            ),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Ganze Serie'),
              subtitle: const Text('Betrifft alle Termine dieser Serie.'),
              onTap: () => Navigator.pop(ctx, 'series'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Abbrechen'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _delete() async {
    final ev = widget.existing!;
    final isSeriesInstance = ev.isRecurring && ev.recurrenceDate != null;

    // Bei Serienterminen zuerst fragen: nur diese Instanz oder ganze Serie?
    var deleteOnlyThis = false;
    if (isSeriesInstance) {
      final scope = await _askSeriesScope(ev, 'löschen');
      if (scope == null) return;
      deleteOnlyThis = scope == 'this';
    }
    if (!mounted) return;

    final dateLabel = DateFormat('d. MMM y', 'de_DE').format(ev.start);
    final ok = await showCountdownDeleteDialog(
      context,
      title: deleteOnlyThis
          ? 'Diesen Termin löschen?'
          : isSeriesInstance
          ? 'Ganze Serie löschen?'
          : 'Termin löschen?',
      message: deleteOnlyThis
          ? '„${ev.summary}" am $dateLabel wird aus der Serie entfernt.'
          : isSeriesInstance
          ? '„${ev.summary}" – die gesamte Serie wird gelöscht. Diese '
                'Aktion kann nicht rückgängig gemacht werden.'
          : '„${ev.summary}" wird endgültig aus der Nextcloud gelöscht.',
    );
    if (!ok) return;

    final notifier = ref.read(eventsControllerProvider.notifier);

    Future<bool> runDelete(bool force) async {
      try {
        if (deleteOnlyThis) {
          await notifier.deleteOccurrence(ev, force: force);
        } else {
          await notifier.deleteEvent(ev, force: force);
        }
        return true;
      } on CalDavException catch (e) {
        if (e.isConflict && mounted) {
          final choice = await showConflictDialog(context);
          if (choice == ConflictChoice.keepMine) return runDelete(true);
          if (choice == ConflictChoice.loadServer) {
            ref.invalidate(eventsControllerProvider);
            return true;
          }
          return false;
        }
        if (mounted) _snack('Löschen fehlgeschlagen: $e');
        return false;
      } catch (e) {
        if (mounted) _snack('Löschen fehlgeschlagen: $e');
        return false;
      }
    }

    setState(() => _busy = true);
    final done = await runDelete(false);
    if (!mounted) return;
    if (done) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collectionsAsync = ref.watch(collectionsProvider);
    final calendars = (collectionsAsync.value ?? const [])
        .where((c) => c.supportsEvents)
        .toList();
    _calendarHref ??= calendars.isNotEmpty ? calendars.first.href : null;

    final templatesEnabled = ref.watch(templatesEnabledProvider).value ?? true;
    final templates =
        ref.watch(eventTemplatesProvider).value ?? const <EventTemplate>[];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEdit ? 'Termin bearbeiten' : 'Neuer Termin',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            RawAutocomplete<EventTemplate>(
              textEditingController: _summaryCtrl,
              focusNode: _summaryFocus,
              optionsBuilder: (v) {
                if (!templatesEnabled || v.text.trim().isEmpty) {
                  return const Iterable<EventTemplate>.empty();
                }
                final q = v.text.toLowerCase();
                return templates.where(
                  (t) =>
                      t.summary.toLowerCase().contains(q) &&
                      t.summary.toLowerCase() != q,
                );
              },
              displayStringForOption: (t) => t.summary,
              onSelected: _applyTemplate,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    autofocus: !_isEdit,
                    textCapitalization: TextCapitalization.sentences,
                    onSubmitted: (_) => onSubmit(),
                    decoration: const InputDecoration(
                      labelText: 'Titel',
                      prefixIcon: Icon(Icons.event),
                      border: OutlineInputBorder(),
                    ),
                  ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 220,
                      maxWidth: 420,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      itemBuilder: (context, i) {
                        final t = options.elementAt(i);
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.bookmark_outline),
                          title: Text(t.summary),
                          subtitle:
                              (t.location != null && t.location!.isNotEmpty)
                              ? Text(t.location!)
                              : null,
                          onTap: () => onSelected(t),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (templatesEnabled)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _saveAsTemplate,
                onChanged: (v) => setState(() => _saveAsTemplate = v ?? false),
                title: const Text('Als Vorlage speichern'),
                secondary: const Icon(Icons.bookmark_add_outlined),
              ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _allDay,
              onChanged: (v) => setState(() => _allDay = v),
              title: const Text('Ganztägig'),
              secondary: const Icon(Icons.today),
            ),
            _DateTimeRow(
              label: 'Beginn',
              date: _startDate,
              time: _allDay ? null : _startTime,
              onPickDate: () => _pickDate(isStart: true),
              onPickTime: () => _pickTime(isStart: true),
            ),
            _DateTimeRow(
              label: 'Ende',
              date: _endDate,
              time: _allDay ? null : _endTime,
              onPickDate: () => _pickDate(isStart: false),
              onPickTime: () => _pickTime(isStart: false),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Ort (optional)',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _reminderMinutes ?? 0,
              decoration: const InputDecoration(
                labelText: 'Erinnerung',
                prefixIcon: Icon(Icons.notifications_outlined),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Aus')),
                DropdownMenuItem(value: 5, child: Text('5 Minuten vorher')),
                DropdownMenuItem(value: 15, child: Text('15 Minuten vorher')),
                DropdownMenuItem(value: 30, child: Text('30 Minuten vorher')),
                DropdownMenuItem(value: 60, child: Text('1 Stunde vorher')),
                DropdownMenuItem(value: 120, child: Text('2 Stunden vorher')),
                DropdownMenuItem(value: 1440, child: Text('1 Tag vorher')),
              ],
              onChanged: (v) => setState(
                () => _reminderMinutes = (v == null || v == 0) ? null : v,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _repeat,
              decoration: const InputDecoration(
                labelText: 'Wiederholen (Serientermin)',
                prefixIcon: Icon(Icons.repeat),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Nie')),
                DropdownMenuItem(value: 'DAILY', child: Text('Täglich')),
                DropdownMenuItem(value: 'WEEKLY', child: Text('Wöchentlich')),
                DropdownMenuItem(
                  value: 'BIWEEKLY',
                  child: Text('Alle 2 Wochen'),
                ),
                DropdownMenuItem(value: 'MONTHLY', child: Text('Monatlich')),
                DropdownMenuItem(value: 'YEARLY', child: Text('Jährlich')),
              ],
              onChanged: (v) => setState(() => _repeat = v ?? 'none'),
            ),
            const SizedBox(height: 12),
            if (_repeat != 'none') ...[
              DropdownButtonFormField<String>(
                initialValue: _repeatEnd,
                decoration: const InputDecoration(
                  labelText: 'Serie endet',
                  prefixIcon: Icon(Icons.event_busy),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'never', child: Text('Endlos')),
                  DropdownMenuItem(
                    value: 'until',
                    child: Text('An einem Datum'),
                  ),
                  DropdownMenuItem(value: 'count', child: Text('Nach Anzahl')),
                ],
                onChanged: (v) => setState(() => _repeatEnd = v ?? 'never'),
              ),
              if (_repeatEnd == 'until') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(
                    _repeatUntil == null
                        ? 'Enddatum wählen'
                        : 'Bis ${DateFormat('d. MMM y', 'de_DE').format(_repeatUntil!)}',
                  ),
                  onPressed: _pickRepeatUntil,
                ),
              ],
              if (_repeatEnd == 'count') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Anzahl Termine:'),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _repeatCount > 1
                          ? () => setState(() => _repeatCount--)
                          : null,
                    ),
                    Text(
                      '$_repeatCount',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _repeatCount < 999
                          ? () => setState(() => _repeatCount++)
                          : null,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
            ],
            if (calendars.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: _calendarHref,
                  decoration: const InputDecoration(
                    labelText: 'Kalender',
                    prefixIcon: Icon(Icons.calendar_month),
                    border: OutlineInputBorder(),
                  ),
                  items: calendars
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.href,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      parseHexColor(c.color) ??
                                      theme.colorScheme.primary,
                                ),
                              ),
                              Flexible(child: Text(c.displayName)),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _calendarHref = v),
                ),
              ),
            if (widget.existing?.isRecurring == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  widget.existing!.recurrenceDate != null
                      ? '🔁 Teil einer Serie – beim Speichern oder Löschen '
                            'kannst du wählen: nur dieser Termin oder die ganze '
                            'Serie.'
                      : '🔁 Serientermin – Änderungen gelten für die ganze '
                            'Serie.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Row(
              children: [
                if (_isEdit)
                  IconButton(
                    onPressed: _busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Löschen',
                    color: theme.colorScheme.error,
                  ),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_busy ? 'Speichern…' : 'Speichern'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.date,
    required this.time,
    required this.onPickDate,
    required this.onPickTime,
  });

  final String label;
  final DateTime date;
  final TimeOfDay? time;
  final VoidCallback onPickDate;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPickDate,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(DateFormat('d. MMM y', 'de_DE').format(date)),
            ),
          ),
          if (time != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onPickTime,
              icon: const Icon(Icons.access_time, size: 16),
              label: Text(time!.format(context)),
            ),
          ],
        ],
      ),
    );
  }
}
