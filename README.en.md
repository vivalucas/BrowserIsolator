# Browser Isolator (BrowserIsolator)

Run multiple isolated Chrome environments on one Mac. Each environment has its own cookies, LocalStorage, passwords, and login state, so you can manage multiple accounts without constantly signing in, signing out, or switching browser profiles.

[中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator has a narrow goal: reliable local browser-environment isolation. It is not a full anti-detection platform and does not promise to bypass website risk controls. It simply keeps browser environments clearly separated for everyday multi-account workflows.

## Features

- **Isolated environments**: each environment uses its own Chrome data directory, keeping login state, cookies, cache, and extension settings separate
- **One-click control**: start or close environments from the main panel or menu bar, double-click an environment row to start it, and close all environments at once; closing waits for Chrome to exit so profile locks are released cleanly
- **Environment details**: the main list focuses on name, status, disk usage, and last-used time; profile paths, debugging ports, and advanced details live in the right-side inspector
- **Custom names**: name a new environment immediately after creating it, or rename it later from the context menu
- **Fingerprint variation**: injects different `navigator.hardwareConcurrency` and `navigator.deviceMemory` values per environment, including newly opened tabs
- **Automatic browser setup**: downloads official Google Chrome on first launch into the app's own data directory
- **Settings panel**: view Chrome status, data folders, language, advanced-detail display options, and Help & Updates
- **Local-first**: configuration, browser files, and profile data stay on your Mac
- **7 languages**: 中文, English, 日本語, 한국어, Deutsch, Français, Русский

## Requirements

- macOS 13 Ventura or later
- Apple Silicon Mac (M1 or later)

The current release is built for `arm64-apple-macosx13.0` and does not support Intel Macs.

If you need a Windows version, see the related project: [MoeMoeGit/ChromeIsolator](https://github.com/MoeMoeGit/ChromeIsolator).

## Installation

### Option 1: Download the DMG

1. Open the [Releases](../../releases) page and download the latest `BrowserIsolator.dmg`
2. Open the DMG and drag `BrowserIsolator.app` into Applications
3. On first launch, macOS may show "cannot verify the developer" or "app is damaged". This is Gatekeeper blocking an unsigned / non-notarized app. Run:

   ```bash
   xattr -cr /Applications/BrowserIsolator.app
   ```

   Then open the app again. You can also right-click the app in Finder, choose Open, and confirm in the dialog.

### Option 2: Build from source

To build only the executable:

```bash
cd BrowserIsolator
swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx13.0
```

Output:

```bash
BrowserIsolator/.build/release/BrowserIsolator
```

To package a double-clickable `.app`:

```bash
./build.sh
```

The app is generated at the repository root as `BrowserIsolator.app`.

## Browser Engine

BrowserIsolator uses its own copy of official Google Chrome. It does not read or modify the Chrome you use every day.

On first launch, Chrome is downloaded to:

```text
~/Library/Application Support/BrowserIsolator/Chromium/Google Chrome.app/
```

The download is about 237 MB. BrowserIsolator checks the download response and Chrome executable before opening the environment management panel.

### macOS may block automatic installation

macOS may show a Privacy & Security prompt saying the app was blocked from modifying apps on your Mac. This can happen because BrowserIsolator copies Chrome into its own Application Support directory.

To fix it:

1. Open **System Settings -> Privacy & Security -> App Management**
2. Allow BrowserIsolator
3. Reopen the app and it will continue installation

### Manual Chrome installation

If automatic download fails:

1. Download [Google Chrome](https://www.google.com/chrome/) or the direct [Chrome DMG](https://dl.google.com/chrome/mac/universal/stable/GGRO/googlechrome.dmg)
2. Open the DMG and copy `Google Chrome.app`
3. Place it in:

   ```text
   ~/Library/Application Support/BrowserIsolator/Chromium/
   ```

Final path:

```text
~/Library/Application Support/BrowserIsolator/Chromium/Google Chrome.app
```

Then reopen BrowserIsolator.

## Usage

- **Start**: click Start on an environment row, double-click the environment row, or use the right-side inspector; if Chrome is unavailable, the port is busy, or the profile is locked, the error appears in the inspector
- **Close**: click Close on a running environment; the row briefly shows Closing until Chrome exits
- **Close all**: use Close All in the toolbar; the app waits for all environments to exit
- **Add**: click Add Environment in the toolbar
- **Rename**: right-click an environment and choose Rename
- **Details**: select an environment and use the right-side inspector to view the profile path, debugging port, errors, actions, and advanced details
- **Delete**: right-click a stopped environment and choose Delete; type the environment name to confirm, then its data is moved to Trash
- **Settings**: use the toolbar gear to open data folders, copy paths, view Chrome version, redownload Chrome, change language, check for updates, open Releases, or view contact details
- **Language**: use the globe menu in the toolbar or the menu bar menu
- **Menu bar**: start, close, change language, check updates, or open the main panel

Running environments are sorted to the top. Each running environment shows its remote debugging port, useful for diagnosing browser connection and fingerprint injection state.

## Data Location

All data is stored at:

```text
~/Library/Application Support/BrowserIsolator/
├── config.json
├── Chromium/
│   └── Google Chrome.app/
└── Profiles/
    ├── p1/
    ├── p2/
    └── p3/
```

To fully remove all data after uninstalling, delete the entire `BrowserIsolator` directory.

## FAQ

### Why not use my existing Chrome?

To avoid touching your daily browser. BrowserIsolator uses its own Chrome copy and its own profile folders, separate from your bookmarks, cookies, passwords, and extensions.

### Can it prevent account bans?

No guarantee. BrowserIsolator focuses on local data isolation and light fingerprint variation. Website risk-control systems vary widely, and this project does not promise detection bypass.

### What fingerprint variation is implemented?

BrowserIsolator uses Chrome DevTools Protocol to inject scripts that set:

- `navigator.hardwareConcurrency`
- `navigator.deviceMemory`

Values are generated from the environment number and remain stable across restarts. BrowserIsolator periodically synchronizes current Chrome DevTools Protocol page targets, so newly opened tabs are injected too. This is lightweight variation, not full device simulation.

### Does video playback work?

Yes. The app uses official Google Chrome, so mainstream video sites and common codecs work normally.

### Does Chrome update automatically?

No. To update Chrome manually, delete:

```text
~/Library/Application Support/BrowserIsolator/Chromium/
```

The next launch downloads Chrome again.

### How many environments can run at once?

There is no hard limit. Running no more than five at once is recommended, depending on memory, CPU, and the pages open in each environment.

## Notes

The letter in the app icon is drawn with MiSans.
