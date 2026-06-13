# App-Icon – „Unser Familien-Organizer"

Gewähltes Icon: **Familie auf dem Kalenderblatt** (Konzept 4). Flach & minimal in den
Markenfarben (Orange `#E8964F`, Creme `#F3EEE4`, Braun `#3E322A`, Sage `#A9C29B`,
Sky `#AFC6DD`, Terracotta `#D89B79`).

![Icon](icon.png)

## Dateien

| Datei | Zweck |
|-------|-------|
| `icon.svg` / `icon.png` | Voll-Icon (1024×1024) – Quelle für Windows-`.ico`, Web und Legacy-Launcher. |
| `icon-foreground.svg` / `icon-foreground.png` | Motiv auf transparentem Grund, in die Adaptive-Safe-Zone skaliert – Vordergrund des Android-Adaptive-Icons (Hintergrund = Creme `#F3EEE4`). |

## Generierung

Die Launcher-Icons werden aus diesen Quellen erzeugt:

```sh
dart run flutter_launcher_icons
```

Die Konfiguration steht in `pubspec.yaml` unter `flutter_launcher_icons:`. Im CI
(GitHub Actions) läuft dieser Schritt automatisch vor jedem Build, daher müssen die
generierten `mipmap-*`-Dateien nicht eingecheckt werden.
