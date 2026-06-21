import 'package:flutter/material.dart';

import '../../core/caldav/ical_parser.dart';

/// Eine Aufgabe (VTODO) inkl. allem, was zum Zurückschreiben nötig ist
/// (Objekt-URL, ETag und roher iCal-Body).
class TaskItem {
  const TaskItem({
    required this.uid,
    required this.summary,
    required this.objectHref,
    required this.etag,
    required this.rawIcal,
    this.description,
    this.due,
    this.completed = false,
    this.priority,
    this.color,
  });

  final String uid;
  final String summary;
  final String? description;
  final DateTime? due;
  final bool completed;
  final int? priority;

  /// URL des CalDAV-Objekts (.ics) – Ziel für PUT/DELETE.
  final String objectHref;

  /// ETag zur Konflikterkennung beim Schreiben.
  final String etag;

  /// Vollständiger iCal-Body des Objekts (wird beim Abhaken modifiziert).
  final String rawIcal;

  /// Listenfarbe (aus der CalDAV-Collection).
  final Color? color;

  /// Wiederkehrende Aufgabe (VTODO mit RRULE)?
  bool get isRecurring => rawIcal.contains('RRULE:');

  factory TaskItem.fromParsed(
    ParsedTodo t, {
    required String objectHref,
    required String etag,
    required String rawIcal,
    Color? color,
  }) {
    return TaskItem(
      uid: t.uid,
      summary: t.summary,
      description: t.description,
      due: t.due,
      completed: t.completed,
      priority: t.priority,
      objectHref: objectHref,
      etag: etag,
      rawIcal: rawIcal,
      color: color,
    );
  }

  TaskItem copyWith({bool? completed, String? etag, String? rawIcal}) {
    return TaskItem(
      uid: uid,
      summary: summary,
      description: description,
      due: due,
      completed: completed ?? this.completed,
      priority: priority,
      objectHref: objectHref,
      etag: etag ?? this.etag,
      rawIcal: rawIcal ?? this.rawIcal,
      color: color,
    );
  }
}

/// Eine Aufgabenliste (CalDAV-Collection, die VTODOs unterstützt).
class TaskList {
  const TaskList({
    required this.href,
    required this.name,
    required this.items,
    this.color,
  });

  final String href;
  final String name;
  final Color? color;
  final List<TaskItem> items;

  int get openCount => items.where((t) => !t.completed).length;

  TaskList withItems(List<TaskItem> newItems) =>
      TaskList(href: href, name: name, color: color, items: newItems);
}
