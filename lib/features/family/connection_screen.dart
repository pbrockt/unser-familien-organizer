import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/account_providers.dart';
import '../../core/auth/nextcloud_account.dart';
import '../../core/caldav/caldav_exception.dart';

/// Verbindung mit der eigenen Nextcloud herstellen.
///
/// Primär per **Login Flow v2** (Anmeldung im Browser, App erhält automatisch
/// ein App-Passwort). Alternativ manuell mit App-Passwort.
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key, this.existing});

  final NextcloudAccount? existing;

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late bool _allowInsecure;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  // Login-Flow-Zustand.
  bool _waitingForLogin = false;
  bool _loginCancelled = false;
  String? _lastLoginUrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _urlCtrl = TextEditingController(text: e?.baseUrl ?? 'https://');
    _userCtrl = TextEditingController(text: e?.username ?? '');
    _passCtrl = TextEditingController(text: e?.appPassword ?? '');
    _allowInsecure = e?.allowInsecureCert ?? false;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool _validUrl() {
    final host = _urlCtrl.text.trim().replaceFirst(RegExp(r'^(https?://)+'), '');
    return host.isNotEmpty && host.contains('.');
  }

  // ---- Login Flow v2 ----

  Future<void> _loginWithBrowser() async {
    if (!_validUrl()) {
      setState(() => _error = 'Bitte eine gültige Server-Adresse eingeben.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final service = ref.read(nextcloudLoginServiceProvider);
    final base = service.normalizeBase(_urlCtrl.text);
    try {
      final init = await service.start(base, allowInsecure: _allowInsecure);
      final opened = await launchUrl(
        Uri.parse(init.loginUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        setState(() {
          _busy = false;
          _error = 'Konnte den Browser nicht öffnen.';
        });
        return;
      }
      _lastLoginUrl = init.loginUrl;
      setState(() {
        _waitingForLogin = true;
        _loginCancelled = false;
      });

      final account = await service.poll(
        init,
        allowInsecure: _allowInsecure,
        isCancelled: () => _loginCancelled || !mounted,
      );
      if (!mounted) return;

      if (account != null) {
        await ref.read(accountProvider.notifier).save(account);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Angemeldet als ${account.username} ✓')),
        );
        Navigator.of(context).pop();
      } else {
        setState(() {
          _waitingForLogin = false;
          _busy = false;
          if (!_loginCancelled) {
            _error = 'Zeitüberschreitung. Bitte erneut versuchen.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _waitingForLogin = false;
          _busy = false;
          _error = 'Anmeldung fehlgeschlagen: $e';
        });
      }
    }
  }

  void _cancelLogin() {
    setState(() {
      _loginCancelled = true;
      _waitingForLogin = false;
      _busy = false;
    });
  }

  // ---- Manuell (App-Passwort) ----

  Future<void> _manualSave() async {
    if (!_validUrl()) {
      setState(() => _error = 'Bitte eine gültige Server-Adresse eingeben.');
      return;
    }
    if (_userCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Benutzername und App-Passwort eingeben.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final account = NextcloudAccount(
      baseUrl: _urlCtrl.text,
      username: _userCtrl.text,
      appPassword: _passCtrl.text,
      allowInsecureCert: _allowInsecure,
    ).normalized();

    try {
      final client = ref.read(caldavClientProvider);
      final collections = await client.listCollections(account);
      await ref.read(accountProvider.notifier).save(account);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            'Verbunden! ${collections.length} Kalender/Listen gefunden.')),
      );
      Navigator.of(context).pop();
    } on CalDavException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Fehler: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Nextcloud verbinden'
            : 'Verbindung bearbeiten'),
      ),
      body: SafeArea(
        child: _waitingForLogin ? _waitingView() : _formView(),
      ),
    );
  }

  Widget _waitingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('Anmeldung im Browser…',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Melde dich im geöffneten Browser bei Nextcloud an und bestätige '
              'den Zugriff. Danach geht es hier automatisch weiter.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (_lastLoginUrl != null)
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(_lastLoginUrl!),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Browser erneut öffnen'),
              ),
            OutlinedButton(
              onPressed: _cancelLogin,
              child: const Text('Abbrechen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Verbinde deine eigene Nextcloud. Am einfachsten per Anmeldung im '
            'Browser – die App erhält automatisch ein App-Passwort.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: const InputDecoration(
              labelText: 'Server-Adresse',
              hintText: 'https://pb.lah-cx.de',
              helperText: 'Nur die Adresse – den Rest macht die App.',
              prefixIcon: Icon(Icons.cloud_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _allowInsecure,
            onChanged: (v) => setState(() => _allowInsecure = v),
            title: const Text('Selbst-signiertes Zertifikat erlauben'),
            subtitle: const Text('Für Heimserver (Unraid) ohne offizielles '
                'TLS-Zertifikat'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            _ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _loginWithBrowser,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login),
            label: Text(_busy ? 'Öffne Browser…' : 'Mit Nextcloud anmelden'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('oder',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: 4),
          Theme(
            data: Theme.of(context)
                .copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('Manuell mit App-Passwort'),
              children: [
                TextField(
                  controller: _userCtrl,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Benutzername',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'App-Passwort',
                    helperText: 'Nextcloud → Einstellungen → Sicherheit → '
                        'App-Passwort',
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _manualSave,
                  icon: const Icon(Icons.link),
                  label: const Text('Verbinden & Testen'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}
