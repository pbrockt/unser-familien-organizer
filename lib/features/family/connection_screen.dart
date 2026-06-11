import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../../core/auth/nextcloud_account.dart';
import '../../core/caldav/caldav_exception.dart';

/// Formular zum Verbinden mit der eigenen Nextcloud.
///
/// Der Nutzer trägt **seine eigene URL**, Benutzername und App-Passwort ein.
/// "Verbinden & Testen" macht einen echten PROPFIND gegen den Server: nur
/// wenn der klappt, werden die Daten verschlüsselt gespeichert.
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key, this.existing});

  /// Bestehendes Konto zum Vorbefüllen (Bearbeiten statt neu verbinden).
  final NextcloudAccount? existing;

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late bool _allowInsecure;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

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

  Future<void> _testAndSave() async {
    if (!_formKey.currentState!.validate()) return;
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
      // Echter Verbindungstest: Collections abrufen (PROPFIND).
      final client = ref.read(caldavClientProvider);
      final collections = await client.listCollections(account);

      await ref.read(accountProvider.notifier).save(account);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Verbunden! ${collections.length} Kalender/Listen gefunden.',
          ),
        ),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Trage deine eigene Nextcloud-Adresse ein. Die App spricht '
                  'direkt per CalDAV mit deinem Server – kein fremdes Konto.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Server-Adresse',
                    hintText: 'https://pb.lah-cx.de',
                    helperText: 'Nur die Adresse deines Servers – den Rest '
                        '(/remote.php/…) hängt die App selbst an.',
                    helperMaxLines: 2,
                    prefixIcon: Icon(Icons.cloud_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    final host = t.replaceFirst(RegExp(r'^(https?://)+'), '');
                    if (host.isEmpty) return 'Server-Adresse eingeben';
                    if (!host.contains('.')) {
                      return 'Vollständige Adresse, z.B. pb.lah-cx.de';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _userCtrl,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Benutzername',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Benutzername eingeben' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'App-Passwort',
                    helperText: 'Nextcloud → Einstellungen → Sicherheit → '
                        'App-Passwort (nicht dein Login-Passwort)',
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'App-Passwort eingeben' : null,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _allowInsecure,
                  onChanged: (v) => setState(() => _allowInsecure = v),
                  title: const Text('Selbst-signiertes Zertifikat erlauben'),
                  subtitle: const Text(
                      'Für Heimserver (Unraid) ohne offizielles TLS-Zertifikat'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  _ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _testAndSave,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(_busy ? 'Teste Verbindung…' : 'Verbinden & Testen'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
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
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
