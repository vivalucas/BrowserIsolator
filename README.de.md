# Browser-Isolator (BrowserIsolator)

Führe mehrere voneinander getrennte Chrome-Umgebungen auf einem Mac aus. Jede Umgebung hat eigene Cookies, LocalStorage, Passwörter und Anmeldestatus, damit mehrere Konten ohne ständiges Ab- und Anmelden nutzbar sind.

[中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator verfolgt ein klares Ziel: lokale Browser-Umgebungen zuverlässig trennen. Es ist keine vollständige Anti-Detection-Plattform und verspricht nicht, Website-Risikokontrollen zu umgehen.

## Funktionen

- **Isolierte Umgebungen**: jede Umgebung nutzt ein eigenes Chrome-Datenverzeichnis
- **Schnelle Steuerung**: Starten, Schließen und Alle schließen im Hauptfenster oder in der Menüleiste; beim Schließen wartet die App auf das Ende von Chrome
- **Umgebungsdetails**: Status, Ordner, Debug-Port, Speicherplatz und letzte Nutzung
- **Eigene Namen und Notizen**: Umgebungen benennen und kurze Notizen für Konto, Kunde oder Zweck hinterlegen
- **Fingerprint-Variation**: unterschiedliche Werte für `navigator.hardwareConcurrency` und `navigator.deviceMemory`, auch in neu geöffneten Tabs
- **Externe Links**: BrowserIsolator als Standardbrowser setzen und festlegen, welche Umgebung Links aus anderen Apps öffnet
- **Automatische Browser-Installation**: offizielles Google Chrome wird beim ersten Start geladen
- **App-Updates**: neue Versionen über Sparkle und GitHub Releases prüfen
- **Lokal zuerst**: Konfiguration und Profildaten bleiben auf dem Mac
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

- **Starten**: Start in einer Umgebungszeile klicken; bei Fehlern zeigt die App eine Meldung
- **Schließen**: Schließen bei einer laufenden Umgebung klicken; bis Chrome beendet ist, erscheint der Status Schließt
- **Alle schließen**: Alle schließen in der Symbolleiste
- **Hinzufügen**: Umgebung hinzufügen in der Symbolleiste
- **Umbenennen / Notizen / Löschen**: per Rechtsklick oder im rechten Detailbereich. Beim Löschen werden Daten in den Papierkorb verschoben
- **Externe Links**: unter **Einstellungen -> Externe Links** die Zielumgebung wählen und BrowserIsolator als Standardbrowser setzen
- **Einstellungen**: Chrome-Status, Datenordner, Erscheinungsbild, Sprache, Updates, Kontakt und Feedback öffnen
- **Sprache wechseln**: Globus-Menü in Symbolleiste oder Menüleiste

## Datenort

```text
~/Library/Application Support/BrowserIsolator/
├── config.json          # Umgebungen, Namen und Notizen
├── Chromium/
└── Profiles/
```

Zum vollständigen Entfernen lösche diesen `BrowserIsolator`-Ordner.

## FAQ

### Warum nicht das vorhandene Chrome verwenden?

Damit dein täglicher Browser unberührt bleibt. BrowserIsolator nutzt eine eigene Chrome-Kopie und eigene Profile.

### Verhindert es Kontosperren?

Nein, das kann nicht garantiert werden. BrowserIsolator bietet lokale Datentrennung und leichte Fingerprint-Variation, aber keine Umgehung von Erkennungssystemen.

### Was macht die Fingerprint-Variation?

Über Chrome DevTools Protocol werden `navigator.hardwareConcurrency` und `navigator.deviceMemory` je Umgebung gesetzt. BrowserIsolator synchronisiert regelmäßig aktuelle page targets, daher werden auch neue Tabs injiziert. Das ist keine vollständige Gerätesimulation.

### Aktualisiert sich Chrome automatisch?

Nein. Lösche zum Aktualisieren `~/Library/Application Support/BrowserIsolator/Chromium/` und starte die App erneut.

### Aktualisiert sich BrowserIsolator automatisch?

Die App kann nach Updates suchen. Nutze „Nach Updates suchen“ in der Menüleiste oder **Einstellungen -> Info & Hilfe**. BrowserIsolator prüft neue Versionen über Sparkle und GitHub Releases.

### Wie öffne ich Links aus anderen Apps in einer bestimmten Umgebung?

Öffne **Einstellungen -> Externe Links**, wähle die Zielumgebung und klicke auf „Als Standardbrowser setzen“. Danach werden http/https-Links aus Mail, Chat-Apps, Notizen und anderen Apps an diese Umgebung weitergegeben. Ist die Browserumgebung noch nicht bereit, zeigt BrowserIsolator eine Meldung und bietet das Kopieren des Links an.
