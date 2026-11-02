# Tenbar

Native macOS-Taskleiste mit Startmenü im Stil von Windows 10. Neuaufbau als Swift Package.

![Tenbar in Aktion](docs/demo.gif)

## Stand (Kern)

- Eine Taskleiste pro Bildschirm. Jedes Fenster erscheint auf dem Bildschirm, auf dem es überwiegend liegt.
- Vollbild: Auf einem Bildschirm mit einer Vollbild-App (z. B. Remotedesktop) wird die Taskleiste ausgeblendet. Das gilt für macOS-Vollbild und für Fenster, die den ganzen Bildschirm bedecken.
- Gruppierung wie bei Windows 10 (umschaltbar per Rechtsklick auf Start oder eine leere Stelle der Taskleiste):
  - **Immer gruppieren:** eine Symbol-Schaltfläche pro App, angeheftete Apps und ihre Fenster verschmelzen. Bei mehreren Fenstern zeigt ein Zähler die Anzahl, ein Klick öffnet die Fensterliste.
  - **Nie gruppieren:** eine beschriftete Schaltfläche pro Fenster, an der Position der angehefteten App.
- Reihenfolge: Angeheftete Apps, die nicht laufen, stehen ganz links. Danach folgen die offenen Apps, zuerst die angehefteten (in Pin-Reihenfolge), dann die übrigen.
- Beschriftungen (standardmäßig an, abschaltbar per Rechtsklick auf Start): Laufende Apps zeigen bei einem Fenster dessen Titel, bei mehreren den App-Namen. Angeheftete Apps ohne Fenster bleiben reine Symbole.
- Klick auf ein einzelnes Fenster holt es nach vorn; ist es bereits aktiv, wird es minimiert.
- Kontextmenü: App öffnen, an die Taskleiste anheften oder lösen, Fenster bzw. alle Fenster schließen, App beenden.
- Untermenü „Neu“ im Kontextmenü laufender Apps: Tenbar liest per Bedienungshilfen das Ablage-/File-Menü der App und bietet dessen „Neu…“-Befehle an, der ⌘N-Befehl zuerst (z. B. „Neues Fenster“ im Finder, „New Solution…“ in Rider). Ein Klick holt die App nach vorn und löst den Menüpunkt aus. Gelesen wird beim Überfahren des Symbols, höchstens alle 2 Sekunden.
- Drag & Drop: Angeheftete Apps lassen sich auf der Taskleiste umsortieren (wird gespeichert), laufende Apps untereinander ebenfalls (nur bis zum Beenden von Tenbar). Eine App aus dem Startmenü auf die Taskleiste ziehen heftet sie an der Ablagestelle an. Start-Kacheln lassen sich ebenso sortieren, und aus der App-Liste gezogene Apps werden an Start angeheftet.
- Startmenü und Taskleiste haben wie bei Windows 10 getrennte Pin-Listen. Im Startmenü bietet das Kontextmenü „An Start anheften“ und „An Taskleiste anheften“.
- Taskleisten-Pins sind pro Bildschirm getrennt (gespeichert pro Display-UUID). Ein Bildschirm ohne eigene Liste zeigt die bisherigen gemeinsamen Pins, bis dort zum ersten Mal etwas angeheftet, gelöst oder verschoben wird. „An Taskleiste anheften“ im Startmenü wirkt auf die Taskleiste des Bildschirms, auf dem das Startmenü geöffnet ist.
- Startmenü: alphabetische Liste aller Apps, Kacheln der angehefteten Apps und ein Ein/Aus-Menü (Sperren, Energie sparen, Abmelden, Neu starten, Herunterfahren). Die letzten drei fragen vorher nach. Dabei schaltet Tenbar „Fenster beim erneuten Anmelden wieder öffnen“ aus, damit nach dem Hochfahren keine Apps wieder geöffnet werden.
- Startmenü-Kacheln pro Bildschirm (Standard) oder auf allen Bildschirmen gleich, umschaltbar per Rechtsklick auf Start → „Startmenü-Kacheln“. Ein Bildschirm ohne eigenes Layout startet mit dem gemeinsamen. Beim Wechsel auf „gleich“ gilt das Layout des Bildschirms, auf dem umgeschaltet wird; die eigenen Layouts bleiben für den Rückweg gespeichert.
- Tooltips: Beim Überfahren einer Kachel oder eines Taskleisten-Symbols erscheint nach kurzer Zeit der Name darüber (eigenes Panel, weil `.help` in Tenbars nicht aktivierenden Panels nicht erscheint).
- Gruppen im Startmenü wie bei Windows 10:
  - Überschrift anklicken zum Umbenennen, an der Überschrift ziehen zum Verschieben der Gruppe.
  - Apps auf eine Kachel, eine Überschrift oder freie Fläche einer Gruppe ziehen verschiebt sie in diese Gruppe.
  - „Hierher ziehen für eine neue Gruppe“ legt eine neue Gruppe an.
  - Rechtsklick auf die Überschrift → „Gruppe vom Start lösen“.
  - Leere Gruppen verschwinden automatisch.
  - Bestehende Start-Pins werden einmalig in eine unbenannte Gruppe übernommen.
- Suche im Startmenü: Das Suchfeld hat beim Öffnen sofort den Fokus, also einfach lostippen. Treffer am Namensanfang stehen vor Wortanfängen und Treffern mitten im Namen. Groß-/Kleinschreibung und Akzente werden ignoriert. ↑/↓ wählt, Enter startet, Escape leert erst die Suche und schließt dann das Menü.
- Startmenü-Größe pro Bildschirm: Die Ecke oben rechts ändert Höhe und Gesamtbreite, die Trennlinie zwischen „Alle Apps“ und „Angeheftet“ verteilt die Breite. Gespeichert wird pro Monitor über die Display-UUID; zurücksetzen per Rechtsklick auf Start. „Alle Apps“ lässt sich pro Monitor ausblenden (oberer Knopf in der linken Leiste des Startmenüs oder Rechtsklick auf Start), dann sind nur die angehefteten Kacheln zu sehen. Der Schieberegler oben rechts (links neben dem Größen-Griff) stellt Schrift- und Symbolgröße pro Monitor ein (80–180 %, Rechtsklick setzt auf 100 % zurück). Der Stift daneben schaltet den Bearbeiten-Modus: Nur dann sind „Gruppe benennen“ und „Hierher ziehen für eine neue Gruppe“ sichtbar. Die Mindesthöhe passt sich an Schriftgröße und sichtbaren Gruppenkopf an, eine Kachelreihe passt immer.
- Fenster erscheinen auf dem Bildschirm, von dem aus sie geöffnet wurden (Startmenü, Klick auf ein Taskleisten-Symbol, „… öffnen“, Untermenü „Neu“): Tenbar wartet bis zu 20 Sekunden auf das neue Fenster der App und verschiebt es dorthin, bei gleicher relativer Position und ggf. verkleinert. Kurz danach auftauchende weitere Fenster (z. B. wiederhergestellte) folgen ebenfalls. Bereits offene Fenster bleiben, wo sie sind.
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

Installieren bzw. eine laufende Version ersetzen:

```sh
osascript -e 'quit app "Tenbar"'; rm -rf /Applications/Tenbar.app && cp -R dist/Tenbar.app /Applications/ && open /Applications/Tenbar.app
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

## Lizenz

[PolyForm Noncommercial 1.0.0](LICENSE.md): Nutzen, Ändern und Weitergeben für private, nicht kommerzielle Zwecke ist erlaubt. Kommerzielle Nutzung ist nicht gestattet.
