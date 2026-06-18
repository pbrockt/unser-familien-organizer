import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../../core/caldav/caldav_client.dart';
import '../../core/caldav/caldav_sharing.dart';

/// Öffnet das Freigabe-Sheet für eine Kalender-/Aufgaben-Collection.
Future<void> showShareSheet(BuildContext context, CalDavCollection collection) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _ShareSheet(collection: collection),
    ),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.collection});
  final CalDavCollection collection;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<CollectionShare> _shares = const [];
  List<Principal> _results = const [];
  bool _loadingShares = true;
  bool _searching = false;
  bool _busy = false;
  String? _error;

  String get _href => widget.collection.href;
  CalDavClient get _client => ref.read(caldavClientProvider);

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShares() async {
    final account = ref.read(accountProvider).value;
    if (account == null) return;
    setState(() => _loadingShares = true);
    try {
      final shares = await _client.listShares(account, _href);
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _loadingShares = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingShares = false;
        _error = '$e';
      });
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    final account = ref.read(accountProvider).value;
    if (account == null || q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await _client.searchPrincipals(account, q);
      if (!mounted) return;
      // Bereits Freigegebene aus den Treffern ausblenden.
      final existing = _shares.map((s) => s.shareHref).toSet();
      setState(() {
        _results = res.where((p) => !existing.contains(p.shareHref)).toList();
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = '$e';
      });
    }
  }

  Future<void> _share(Principal p, bool readWrite) async {
    final account = ref.read(accountProvider).value;
    if (account == null) return;
    setState(() => _busy = true);
    try {
      await _client.setShare(
        account,
        _href,
        shareHref: p.shareHref,
        readWrite: readWrite,
      );
      _searchCtrl.clear();
      _results = const [];
      await _loadShares();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Für ${p.displayName} freigegeben ✓')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Freigabe fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unshare(CollectionShare s) async {
    final account = ref.read(accountProvider).value;
    if (account == null) return;
    setState(() => _busy = true);
    try {
      await _client.removeShare(account, _href, shareHref: s.shareHref);
      await _loadShares();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Entfernen fehlgeschlagen: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAccessAndShare(Principal p) async {
    final rw = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Bearbeiten'),
              subtitle: const Text('Darf Einträge ändern'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Nur lesen'),
              subtitle: const Text('Darf nur ansehen'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (rw != null) await _share(p, rw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.group_add_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Freigeben: ${widget.collection.displayName}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              autocorrect: false,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                labelText: 'Benutzer oder Gruppe suchen',
                hintText: 'z. B. Name, Benutzername oder „Eltern"',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in _results)
                      ListTile(
                        leading: CircleAvatar(
                          child: p.isGroup
                              ? const Icon(Icons.group, size: 20)
                              : Text(
                                  p.displayName.isNotEmpty
                                      ? p.displayName[0].toUpperCase()
                                      : '?',
                                ),
                        ),
                        title: Text(p.displayName),
                        subtitle: Text(
                          p.isGroup ? 'Gruppe' : (p.email ?? 'Benutzer'),
                        ),
                        trailing: const Icon(Icons.add),
                        onTap: _busy ? null : () => _pickAccessAndShare(p),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text('Aktuelle Freigaben', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            if (_loadingShares)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              )
            else if (_shares.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Noch nicht freigegeben.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              )
            else
              for (final s in _shares)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(s.displayName),
                  subtitle: Text(s.readWrite ? 'Bearbeiten' : 'Nur lesen'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Freigabe entfernen',
                    onPressed: _busy ? null : () => _unshare(s),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
