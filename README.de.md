# Browser-Isolator (BrowserIsolator)

Führe mehrere voneinander getrennte Chrome-Umgebungen auf einem Mac aus. Jede Umgebung hat eigene Cookies, LocalStorage, Passwörter und Anmeldestatus, damit mehrere Konten ohne ständiges Ab- und Anmelden nutzbar sind.

[中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator verfolgt ein klares Ziel: lokale Browser-Umgebungen zuverlässig trennen. Es ist keine vollständige Anti-Detection-Plattform und verspricht nicht, Website-Risikokontrollen zu umgehen.

## Funktionen

- **Isolierte Umgebungen**: jede Umgebung nutzt ein eigenes Chrome-Datenverzeichnis
- **Schnelle Steuerung**: Starten, Schließen und Alle schließen im Hauptfenster oder in der Menüleiste; ein Doppelklick auf eine Umgebungszeile startet sie, und beim Schließen wartet die App auf das Ende von Chrome
- **Umgebungsdetails**: die linke Liste zeigt Status, Speicherplatz und letzte Nutzung; der rechte Detailbereich zeigt Profilpfad, Ausführungsmodus, Fehler, Aktionen und erweiterte Details. Debug-Ports erscheinen nur bei Bedarf in den erweiterten Details
- **Eigene Namen und Notizen**: Umgebungen benennen und kurze Notizen für Konto, Kunde oder Zweck hinterlegen
- **Sicheres Löschen**: beim Löschen muss der Umgebungsname eingegeben werden; die Daten werden in den Papierkorb verschoben
- **Basismodus zuerst**: standardmäßig wird nur das Profil getrennt, ohne Debug-Port oder Skript-Injektion in Seiten
- **Optionaler Variationsmodus**: pro Umgebung in den Einstellungen aktivierbar; aktivierte Umgebungen injizieren beim nächsten Start `navigator.hardwareConcurrency` und `navigator.deviceMemory`
- **Externe Links**: BrowserIsolator als Standardbrowser setzen und festlegen, welche Umgebung Links aus anderen Apps öffnet; ist kein Ziel verfügbar, zeigt die App eine Meldung statt den Link zu verlieren
- **Automatische Browser-Installation**: offizielles Google Chrome wird beim ersten Start geladen
- **Einstellungen**: Chrome-Status und Version, Datenordner, Pfade kopieren, Chrome erneut laden, externe Links, Sprache, Erscheinungsbild, erweiterte Details, Updates, Kontakt und Feedback
- **Konfigurationswiederherstellung**: wenn `config.json` beschädigt oder unlesbar ist, lädt BrowserIsolator Standardwerte und sichert die beschädigte Datei nach Möglichkeit
- **Lokal zuerst**: Konfiguration, Chrome und Profildaten bleiben auf dem Mac; BrowserIsolator lädt keine Nutzerdaten hoch und sammelt sie nicht
- **7 Sprachen**: 中文, English, 日本語, 한국어, Deutsch, Français, Русский

## Anforderungen

- macOS 13 Ventura oder neuer
- Apple Silicon Mac (M1 oder neuer)

Die aktuelle Version ist für `arm64-apple-macosx13.0` gebaut und unterstützt keine Intel Macs.

## Installation

### Option 1: DMG herunterladen

1. Lade die neueste `BrowserIsolator.dmg` von [Releases](../../releases)
2. Öffne das DMG und ziehe `BrowserIsolator.app` in Programme
3. Wenn macOS beim ersten Start den Entwickler nicht verifizieren kann oder die App als beschädigt meldet:

   ```bash
   xattr -cr /Applications/BrowserIsolator.app
   ```

Spätere App-Updates findest du unter **Einstellungen -> Info & Hilfe -> Nach Updates suchen**. Die Erstinstallation erfolgt weiterhin über das DMG auf der Releases-Seite.

### Option 2: Aus dem Quellcode bauen

Nur ausführbare Datei:

```bash
cd BrowserIsolator
swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx13.0
```

Als `.app` paketieren:

```bash
./build.sh
```

## Browser-Engine

BrowserIsolator verwendet eine eigene Kopie des offiziellen Google Chrome. Dein normales Chrome wird nicht gelesen oder verändert.

Speicherort:

```text
~/Library/Application Support/BrowserIsolator/Chromium/Google Chrome.app/
```

Falls der automatische Download fehlschlägt, lade Google Chrome manuell herunter und lege `Google Chrome.app` in `~/Library/Application Support/BrowserIsolator/Chromium/` ab.

## Verwendung

- **Starten**: Start in einer Umgebungszeile klicken, die Zeile doppelklicken oder den rechten Detailbereich nutzen; bei Fehlern zeigt die App eine Meldung
- **Schließen**: Schließen bei einer laufenden Umgebung klicken; bis Chrome beendet ist, erscheint der Status Schließt
- **Alle schließen**: Alle schließen in der Symbolleiste
- **Hinzufügen**: Umgebung hinzufügen in der Symbolleiste
- **Umbenennen / Notizen / Löschen**: per Rechtsklick oder im rechten Detailbereich. Beim Löschen werden Daten in den Papierkorb verschoben
- **Externe Links**: unter **Einstellungen -> Externe Links** die Zielumgebung wählen und BrowserIsolator als Standardbrowser setzen. Ist die Umgebung noch nicht bereit oder gibt es keine nutzbare Umgebung, lässt sich der Link kopieren; wenn keine Umgebung verfügbar ist, kann auch das Hauptfenster geöffnet werden
- **Einstellungen**: Chrome-Status, Datenordner, Pfade kopieren, Chrome erneut laden, Erscheinungsbild, Sprache, Updates, Kontakt und Feedback öffnen. Chrome erneut laden ist nur verfügbar, wenn keine Umgebung startet, läuft oder gerade schließt
- **Variationsmodus**: pro Umgebung in den Einstellungen aktivieren. Laufende Umgebungen können nicht geändert werden; erst schließen, dann beim nächsten Start wirksam
- **Sprache wechseln**: Globus-Menü in Symbolleiste oder Menüleiste

## Datenort

```text
~/Library/Application Support/BrowserIsolator/
├── config.json          # Umgebungen, Namen und Notizen
├── Chromium/
│   └── Google Chrome.app/
└── Profiles/
    ├── p1/
    ├── p2/
    └── p3/
```

Zum vollständigen Entfernen lösche diesen `BrowserIsolator`-Ordner.

Wenn `config.json` beschädigt ist oder nicht gelesen werden kann, zeigt BrowserIsolator eine Warnung, lädt die Standardkonfiguration und versucht, die Originaldatei als `config.corrupt-<timestamp>.json` zu behalten.

## FAQ

### Warum nicht das vorhandene Chrome verwenden?

Damit dein täglicher Browser unberührt bleibt. BrowserIsolator nutzt eine eigene Chrome-Kopie und eigene Profile.

### Verhindert es Kontosperren?

Nein, das kann nicht garantiert werden. BrowserIsolator konzentriert sich auf lokale Datentrennung und bietet bei Bedarf leichten Variationsmodus, aber keine Umgehung von Erkennungssystemen.

### Was macht der Variationsmodus?

Standardmäßig wird nichts injiziert. BrowserIsolator priorisiert den Basismodus und trennt nur lokale Profildaten.

Wenn der Variationsmodus in den Einstellungen aktiviert ist, setzt BrowserIsolator beim nächsten Start über Chrome DevTools Protocol `navigator.hardwareConcurrency` und `navigator.deviceMemory` je Umgebung. Aktuelle page targets werden regelmäßig synchronisiert, daher werden auch neue Tabs injiziert. Das ist keine vollständige Gerätesimulation.

Dieser Modus betrifft Chrome-Startparameter und CDP-Nutzung, daher kann er bei laufender Umgebung nicht geändert werden.

### Aktualisiert sich Chrome automatisch?

Nein. Nutze zum Aktualisieren zuerst **Einstellungen -> Chrome erneut laden**. Alle Umgebungen müssen gestoppt sein und dürfen nicht starten oder schließen. Alternativ kannst du `~/Library/Application Support/BrowserIsolator/Chromium/` löschen und die App erneut starten.

### Aktualisiert sich BrowserIsolator automatisch?

Die App kann nach Updates suchen. Nutze „Nach Updates suchen“ in der Menüleiste oder **Einstellungen -> Info & Hilfe**. BrowserIsolator prüft neue Versionen über Sparkle und GitHub Releases.

### Wie öffne ich Links aus anderen Apps in einer bestimmten Umgebung?

Öffne **Einstellungen -> Externe Links**, wähle die Zielumgebung und klicke auf „Als Standardbrowser setzen“. Danach werden http/https-Links aus Mail, Chat-Apps, Notizen und anderen Apps an diese Umgebung weitergegeben. Ist die Browserumgebung noch nicht bereit oder gibt es keine nutzbare Umgebung, zeigt BrowserIsolator eine Meldung und bietet das Kopieren des Links an. Wenn keine Umgebung verfügbar ist, kann auch das Hauptfenster geöffnet werden.
