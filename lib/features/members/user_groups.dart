import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/account_providers.dart';
import '../../core/auth/nextcloud_account.dart';
import '../study/study_settings.dart';

/// Nextcloud-Gruppen des angemeldeten Benutzers (Gruppen-IDs). Wird beim Start
/// und bei jeder Synchronisation frisch vom Server geladen und gerätelokal
/// gecacht – damit z. B. Eltern-Rechte aus der Gruppenzugehörigkeit folgen
/// können, auch offline.
final userGroupsProvider =
    AsyncNotifierProvider<UserGroupsController, List<String>>(
      UserGroupsController.new,
    );

class UserGroupsController extends AsyncNotifier<List<String>> {
  static const _key = 'user_groups';
  bool _disposed = false;

  @override
  Future<List<String>> build() async {
    ref.onDispose(() => _disposed = true);
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getStringList(_key) ?? const <String>[];
    final account = ref.read(accountProvider).value;
    if (account != null) {
      // Sofort den Cache zeigen, im Hintergrund frisch holen.
      Future.microtask(() => _refresh(account));
    }
    return cached;
  }

  Future<void> _refresh(NextcloudAccount account) async {
    try {
      final groups = await ref
          .read(caldavClientProvider)
          .fetchUserGroups(account);
      if (_disposed) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, groups);
      state = AsyncData(groups);
    } catch (_) {
      // Offline / keine Rechte → gecachter Stand bleibt erhalten.
    }
  }
}

/// Vom Nutzer gewählte Nextcloud-Gruppe, die Eltern-Rechte gewährt. `null` =
/// automatische Erkennung (Gruppenname enthält „eltern"/„parent"). Gerätelokal.
final parentGroupProvider =
    AsyncNotifierProvider<ParentGroupController, String?>(
      ParentGroupController.new,
    );

class ParentGroupController extends AsyncNotifier<String?> {
  static const _key = 'parent_group';

  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> set(String? group) async {
    final prefs = await SharedPreferences.getInstance();
    if (group == null || group.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, group);
    }
    state = AsyncData(group);
  }
}

bool _looksLikeParentGroup(String g) {
  final n = g.toLowerCase();
  return n.contains('eltern') || n.contains('parent');
}

/// Hat der Nutzer laut Gruppen Eltern-Rechte? Ist eine Gruppe [selected]
/// gewählt, zählt nur diese; sonst automatische Erkennung („eltern"/„parent").
/// Reine Funktion (testbar).
bool isParentByGroups({
  required List<String> groups,
  required String? selected,
}) {
  if (selected != null && selected.isNotEmpty) {
    return groups.any((g) => g.toLowerCase() == selected.toLowerCase());
  }
  return groups.any(_looksLikeParentGroup);
}

/// Effektiver Eltern-Modus: manueller Geräte-Schalter ODER Mitgliedschaft in
/// der (erkannten/gewählten) Eltern-Gruppe.
final effectiveParentModeProvider = Provider<bool>((ref) {
  final manual = ref.watch(parentModeProvider).value ?? false;
  final groups = ref.watch(userGroupsProvider).value ?? const <String>[];
  final selected = ref.watch(parentGroupProvider).value;
  return manual || isParentByGroups(groups: groups, selected: selected);
});
