# Tenbar

Native macOS-Taskleiste mit Startmenü im Stil von Windows 10. Neuaufbau als Swift Package.

## Stand (Kern)

- Eine Taskleiste pro Bildschirm. Jedes Fenster erscheint auf dem Bildschirm, auf dem es überwiegend liegt.
- Gruppierung wie bei Windows 10 (umschaltbar per Rechtsklick auf Start oder eine leere Stelle der Taskleiste):
  - **Immer gruppieren:** eine Symbol-Schaltfläche pro App, angeheftete Apps und ihre Fenster verschmelzen. Bei mehreren Fenstern zeigt ein Zähler die Anzahl, ein Klick öffnet die Fensterliste.
  - **Nie gruppieren:** eine beschriftete Schaltfläche pro Fenster, an der Position der angehefteten App.
- Beschriftungen (standardmäßig an, abschaltbar per Rechtsklick auf Start): Laufende Apps zeigen bei einem Fenster dessen Titel, bei mehreren den App-Namen. Angeheftete Apps ohne Fenster bleiben reine Symbole.
- Klick auf ein einzelnes Fenster holt es nach vorn; ist es bereits aktiv, wird es minimiert.
- Kontextmenü: App öffnen, an die Taskleiste anheften oder lösen, Fenster bzw. alle Fenster schließen, App beenden.
- Drag & Drop: Angeheftete Apps lassen sich auf der Taskleiste umsortieren (wird gespeichert), laufende Apps untereinander ebenfalls (nur bis zum Beenden von Tenbar). Eine App aus dem Startmenü auf die Taskleiste ziehen heftet sie an der Ablagestelle an. Start-Kacheln lassen sich ebenso sortieren, und aus der App-Liste gezogene Apps werden an Start angeheftet.
- Startmenü und Taskleiste haben wie bei Windows 10 getrennte Pin-Listen. Im Startmenü bietet das Kontextmenü „An Start anheften“ und „An Taskleiste anheften“.
- Taskleisten-Pins sind pro Bildschirm getrennt (gespeichert pro Display-UUID). Ein Bildschirm ohne eigene Liste zeigt die bisherigen gemeinsamen Pins, bis dort zum ersten Mal etwas angeheftet, gelöst oder verschoben wird. „An Taskleiste anheften“ im Startmenü wirkt auf die Taskleiste des Bildschirms, auf dem das Startmenü geöffnet ist.
- Startmenü: alphabetische Liste aller Apps, Kacheln der angehefteten Apps und ein Ein/Aus-Menü (Sperren, Energie sparen, Abmelden, Neu starten, Herunterfahren). Die letzten drei fragen vorher nach.
- Startmenü-Größe pro Bildschirm: Die Ecke oben rechts ändert Höhe und Gesamtbreite, die Trennlinie zwischen „Alle Apps“ und „Angeheftet“ verteilt die Breite. Gespeichert wird pro Monitor über die Display-UUID; zurücksetzen per Rechtsklick auf Start.
- Die Fensterliste aktualisiert sich über `AXObserver`- und `NSWorkspace`-Ereignisse statt durch ständige Abfrage. Ein Sicherheitsabgleich läuft alle 5 Sekunden.
- Fenster-IDs bleiben stabil, auch wenn sich ein Titel ändert. Die Reihenfolge bleibt dabei erhalten.

## Aufbau

```
Sources/TenbarCore/   Reine Logik, getestet (Reihenfolge, Anheften, Einstellungen, Geometrie, App-Suche, Energieaktionen)
Sources/Tenbar/       App: WindowTracker (Bedienungshilfen-API), AppCatalog, Taskleisten-Panels, SwiftUI-Ansichten
Tests/                Swift-Testing-Tests für TenbarCore
Resources/Info.plist
build.sh
```

## Entwickeln und bauen

Voraussetzungen: macOS 14 oder neuer und Xcode bzw. die Command Line Tools.

```sh
swift build        # Debug-Build
swift test         # Tests
./build.sh         # dist/Tenbar.app (Universal) + dist/Tenbar-<Version>.zip
```

`build.sh` signiert ad hoc. Mit `SIGN_IDENTITY="Developer ID Application: …" ./build.sh` wird stattdessen mit einem eigenen Zertifikat signiert.

## Berechtigungen

- **Bedienungshilfen:** nötig für die Fensterliste. Aktivieren unter Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen.
  Bei Ad-hoc-Signatur ändert sich die Signatur mit jedem Build, deshalb muss der Zugriff nach jedem Neubau neu erteilt werden. Mit einem festen Zertifikat (`SIGN_IDENTITY`) bleibt er erhalten.
- **Automation (System Events):** macOS fragt bei der ersten Energieaktion danach.

## Nächste Ausbaustufen

- Option „Gruppieren, wenn die Taskleiste voll ist“
- Einstellungsfenster (Taskleiste pro Bildschirm, Breiten, Schriftgrößen)
- „Zuletzt verwendet“ im Startmenü
- Neue Fenster auf dem Bildschirm der geklickten Taskleiste öffnen
