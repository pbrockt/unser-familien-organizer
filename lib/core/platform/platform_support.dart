import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Plattform-Weichen, um Android-spezifische Features (Benachrichtigungen,
/// Home-Widgets, Hintergrund-Sync) auf dem Desktop sauber abzuschalten.
bool get isAndroid => !kIsWeb && Platform.isAndroid;

bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
