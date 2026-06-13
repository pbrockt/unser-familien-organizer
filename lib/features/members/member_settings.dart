import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/account_providers.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/utils/hex_color.dart';
import '../calendar/calendar_event.dart';

/// Lokale Anpassung eines Kalenders/einer Person: eigener Name, eigene Farbe,
/// Sichtbarkeit. Gilt nur auf diesem Gerät (kein Eingriff in Nextcloud).
class MemberSetting {
  const MemberSetting({this.name, this.colorHex, this.hidden = false});

  final String? name;
  final String? colorHex;
  final bool hidden;

  MemberSetting copyWith({
    String? name,
    String? colorHex,
    bool? hidden,
    bool clearColor = false,
  }) =>
      MemberSetting(
        name: name ?? this.name,
        colorHex: clearColor ? null : (colorHex ?? this.colorHex),
        hidden: hidden ?? this.hidden,
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'color': colorHex, 'hidden': hidden};

  factory MemberSetting.fromJson(Map<String, dynamic> j) => MemberSetting(
        name: j['name'] as String?,
        colorHex: j['color'] as String?,
        hidden: (j['hidden'] as bool?) ?? false,
      );
}

/// Persistierte Member-Einstellungen, gekeyt nach Collection-href.
final memberSettingsProvider = AsyncNotifierProvider<MemberSettingsController,
    Map<String, MemberSetting>>(MemberSettingsController.new);

class MemberSettingsController
    extends AsyncNotifier<Map<String, MemberSetting>> {
  static const _key = 'member_settings';

  @override
  Future<Map<String, MemberSetting>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) =>
          MapEntry(k, MemberSetting.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  Future<void> _update(String href, MemberSetting setting) async {
    final current = Map<String, MemberSetting>.of(state.value ?? {});
    current[href] = setting;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(current.map((k, v) => MapEntry(k, v.toJson()))),
    );
    state = AsyncData(current);
  }

  MemberSetting _of(String href) =>
      state.value?[href] ?? const MemberSetting();

  Future<void> setName(String href, String? name) =>
      _update(href, _of(href).copyWith(name: (name ?? '').trim().isEmpty ? null : name!.trim()));

  Future<void> setColorHex(String href, String? colorHex) => _update(
      href,
      colorHex == null
          ? _of(href).copyWith(clearColor: true)
          : _of(href).copyWith(colorHex: colorHex));

  Future<void> setHidden(String href, bool hidden) =>
      _update(href, _of(href).copyWith(hidden: hidden));
}

/// Ein anzeigbares „Mitglied" = ein Kalender/eine Liste mit effektivem
/// Namen/Farbe.
typedef Member = ({
  String href,
  String name,
  Color color,
  bool hidden,
  bool supportsEvents,
  bool supportsTodos,
});

/// Wendet Mitglieder-Anpassungen auf Termine an: blendet ausgeblendete
/// Kalender aus und überschreibt die Farbe. Reine Funktion (auch im
/// Hintergrund-Isolate nutzbar).
List<CalendarEvent> filterVisibleEvents(
  List<CalendarEvent> events,
  Map<String, MemberSetting> settings,
) {
  if (settings.isEmpty) return events;
  final out = <CalendarEvent>[];
  for (final e in events) {
    final s = settings[e.calendarHref];
    if (s == null) {
      out.add(e);
      continue;
    }
    if (s.hidden) continue;
    final override = parseHexColor(s.colorHex);
    out.add(override != null ? e.copyWith(color: override) : e);
  }
  return out;
}

/// Mitglieder-Liste (alle Collections) mit angewandten Anpassungen.
final membersProvider = Provider.autoDispose<List<Member>>((ref) {
  final collections = ref.watch(collectionsProvider).value ?? const [];
  final settings = ref.watch(memberSettingsProvider).value ?? const {};
  final result = <Member>[];
  for (final c in collections) {
    final s = settings[c.href];
    final name =
        (s?.name != null && s!.name!.isNotEmpty) ? s.name! : c.displayName;
    final color =
        parseHexColor(s?.colorHex) ?? parseHexColor(c.color) ?? AppTheme.seed;
    result.add((
      href: c.href,
      name: name,
      color: color,
      hidden: s?.hidden ?? false,
      supportsEvents: c.supportsEvents,
      supportsTodos: c.supportsTodos,
    ));
  }
  return result;
});
