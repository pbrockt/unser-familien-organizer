import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_view.dart';

/// Einkaufslisten-Bereich.
///
/// Phase 6: Einkaufsliste als spezielle VTODO-Collection in Nextcloud.
/// Artikel = VTODO (Name in SUMMARY, Menge in DESCRIPTION),
/// abgehakt = STATUS:COMPLETED, Kategorie = CATEGORIES.
class ShoppingScreen extends StatelessWidget {
  const ShoppingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Einkauf')),
      body: const PlaceholderView(
        icon: Icons.shopping_cart,
        title: 'Einkaufsliste',
        subtitle: 'Gemeinsam sammeln, unterwegs abhaken.\n'
            'Phase 6: VTODO-Collection per CalDAV mit Nextcloud.',
      ),
    );
  }
}
