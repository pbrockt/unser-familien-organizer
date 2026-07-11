import 'package:flutter/material.dart';

import '../utils/hex_color.dart';

/// Öffnet einen Farbmischer (Sättigungs-/Helligkeits-Feld + Farbton-Balken +
/// HEX-Eingabe, wie in Nextcloud) und liefert die gewählte Farbe – oder `null`
/// bei Abbruch.
Future<Color?> showColorPickerSheet(
  BuildContext context, {
  required Color initial,
  String title = 'Farbe wählen',
}) {
  return showModalBottomSheet<Color>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _ColorPickerSheet(initial: initial, title: title),
    ),
  );
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({required this.initial, required this.title});
  final Color initial;
  final String title;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(
    text: toHexRgb(widget.initial).substring(1).toUpperCase(),
  );

  Color get _color => _hsv.toColor();

  void _setHsv(HSVColor v) {
    setState(() => _hsv = v);
    final hex = toHexRgb(v.toColor()).substring(1).toUpperCase();
    if (_hex.text.toUpperCase() != hex) _hex.text = hex;
  }

  void _onHexChanged(String raw) {
    final c = parseHexColor(raw);
    if (c != null) setState(() => _hsv = HSVColor.fromColor(c));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            // Sättigung (x) / Helligkeit (y).
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 170,
                width: double.infinity,
                child: _SvField(
                  hsv: _hsv,
                  onChanged: (s, v) =>
                      _setHsv(_hsv.withSaturation(s).withValue(v)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _color,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _HueBar(
                    hue: _hsv.hue,
                    onChanged: (h) => _setHsv(_hsv.withHue(h)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _hex,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'HEX',
                prefixText: '#',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onHexChanged,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _color),
                  child: const Text('Auswählen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sättigungs-/Helligkeits-Feld: links weiß → rechts Farbton, oben hell → unten
/// schwarz. Tippen/Ziehen setzt Sättigung (x) und Helligkeit (y).
class _SvField extends StatelessWidget {
  const _SvField({required this.hsv, required this.onChanged});
  final HSVColor hsv;
  final void Function(double sat, double val) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        void handle(Offset p) {
          final s = (p.dx / w).clamp(0.0, 1.0);
          final v = (1 - p.dy / h).clamp(0.0, 1.0);
          onChanged(s, v);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: Stack(
            children: [
              // Voller Farbton.
              Positioned.fill(
                child: ColoredBox(
                  color: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                ),
              ),
              // Sättigung: weiß (links) → transparent (rechts).
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.white, Colors.transparent],
                    ),
                  ),
                ),
              ),
              // Helligkeit: transparent (oben) → schwarz (unten).
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
              ),
              // Auswahl-Kringel.
              Positioned(
                left: (hsv.saturation * w) - 9,
                top: ((1 - hsv.value) * h) - 9,
                child: _Thumb(color: hsv.toColor()),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Farbton-Balken (Regenbogen), Tippen/Ziehen setzt den Farbton.
class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});
  final double hue;
  final void Function(double hue) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        void handle(Offset p) => onChanged((p.dx / w).clamp(0.0, 1.0) * 360.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (d) => handle(d.localPosition),
          onPanUpdate: (d) => handle(d.localPosition),
          child: SizedBox(
            height: 26,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFF0000),
                          Color(0xFFFFFF00),
                          Color(0xFF00FF00),
                          Color(0xFF00FFFF),
                          Color(0xFF0000FF),
                          Color(0xFFFF00FF),
                          Color(0xFFFF0000),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: (hue / 360.0 * w) - 9,
                  top: -1,
                  child: _Thumb(
                    color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
      ),
    );
  }
}
