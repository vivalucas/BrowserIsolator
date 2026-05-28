# Browser Isolator (BrowserIsolator)

Run multiple isolated Chrome environments on one Mac. Each environment has its own cookies, LocalStorage, passwords, and login state, so you can manage multiple accounts without constantly signing in, signing out, or switching browser profiles.

[中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator has a narrow goal: reliable local browser-environment isolation. It is not a full anti-detection platform and does not promise to bypass website risk controls. It simply keeps browser environments clearly separated for everyday multi-account workflows.

## Features

- **Isolated environments**: each environment uses its own Chrome data directory, keeping login state, cookies, cache, and extension settings separate
- **Quick control**: start or close environments from the main panel or menu bar, click a selected environment row again to start it, and close all environments at once; closing waits for Chrome to exit so profile locks are released cleanly
- **Environment details**: the main list focuses on name, status, disk usage, and last-used time; the right-side inspector shows profile path, run mode, actions, and advanced details. Debug ports appear only in advanced details when applicable
- **Custom names and notes**: name a new environment immediately after creating it, rename it later, or add a short note for account, client, or workflow details
- **Safe deletion**: deleting an environment requires typing its name, then its profile data is moved to Trash
- **Basic Mode by default**: isolates profile data without a debug port or page script injection, keeping behavior close to normal Chrome
- **Optional Variation Mode**: enable lightweight variation per environment in Settings; enabled environments inject stable `navigator.hardwareConcurrency` and `navigator.deviceMemory` values on next launch
- **External link routing**: set BrowserIsolator as the system default browser and choose which environment should receive links opened from other apps; if no target is available, the app prompts instead of dropping the link
- **Automatic browser setup**: downloads official Google Chrome on first launch into the app's own data directory
- **Settings panel**: view Chrome status, data folders, external-link behavior, language, appearance mode, advanced-detail display options, version updates, author contact, and feedback links
- **Config recovery**: if `config.json` is corrupt or unreadable, BrowserIsolator loads defaults and tries to preserve the bad file as a timestamped backup
- **Local-first**: configuration, browser files, and profile data stay on your Mac; BrowserIsolator does not upload or collect user data
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

Future app updates can be checked from **Settings -> About & Support -> Check for Updates**. BrowserIsolator uses Sparkle to fetch updates from GitHub Releases; the first install still starts from the Releases DMG.

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

macOS may show a Privacy & Security prompt saying the app was blocked from modifying apps on your Mac. This can happen because BrowserIsolator copies Chrome into its own Application Support directory; if you trust this app, allow it so the bundled Chrome installation can finish.

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

- **Start**: click Start on an environment row, click a selected environment row again, or use the right-side inspector; if Chrome is unavailable, the port is busy, or the profile is locked, the error appears in the inspector
- **Close**: click Close on a running environment; the row briefly shows Closing until Chrome exits
- **Close all**: use Close All in the toolbar; the app waits for all environments to exit
- **Add**: click Add Environment in the toolbar
- **Rename**: right-click an environment and choose Rename
- **Notes**: add a short note from the inspector or the environment context menu to record account, client, or purpose
- **Details**: select an environment and use the right-side inspector to view the profile path, run mode, errors, actions, and advanced details
- **Delete**: right-click a stopped environment and choose Delete; type the environment name to confirm, then its data is moved to Trash
- **External links**: use Settings -> External Links to choose which environment receives links opened from other apps, and optionally set BrowserIsolator as the default browser. If the browser environment is not ready yet, or if no usable environment exists, the app shows the link and lets you copy it; when no environment is available, it can also open the main panel
- **Settings**: use the toolbar gear to open data folders, copy paths, view Chrome version, redownload Chrome, configure external links, change language or appearance mode, check for updates, open the release page, view author contact, or submit feedback. Redownloading Chrome is available only when no environment is starting, running, or closing
- **Variation Mode**: enable it per environment in Settings. Running environments cannot be changed; close them first and restart for the change to take effect
- **Language**: use the globe menu in the toolbar or the menu bar menu
- **Menu bar**: start, close, close all environments, change language, check updates, or open the main panel

Running environments are sorted to the top. Environments with Variation Mode enabled expose their remote debugging port only in advanced details while running.

## Data Location

All data is stored at:

```text
~/Library/Application Support/BrowserIsolator/
├── config.json          # environments, custom names, and notes
├── Chromium/
│   └── Google Chrome.app/
└── Profiles/
    ├── p1/
    ├── p2/
    └── p3/
```

To fully remove all data after uninstalling, delete the entire `BrowserIsolator` directory.

If `config.json` is corrupt or cannot be read, BrowserIsolator shows an alert, loads the default configuration, and tries to preserve the original file as `config.corrupt-<timestamp>.json`.

## FAQ

### Why not use my existing Chrome?

To avoid touching your daily browser. BrowserIsolator uses its own Chrome copy and its own profile folders, separate from your bookmarks, cookies, passwords, and extensions.

### Can it prevent account bans?

No guarantee. BrowserIsolator focuses on local data isolation and offers light Variation Mode only when you enable it. Website risk-control systems vary widely, and this project does not promise detection bypass.

### What does Variation Mode do?

By default, nothing is injected. BrowserIsolator prioritizes Basic Mode: it isolates local profile data without opening a debug port.

If you enable Variation Mode for an environment in Settings, the next launch uses Chrome DevTools Protocol to inject scripts that set:

- `navigator.hardwareConcurrency`
- `navigator.deviceMemory`

Values are generated from the environment number and remain stable across restarts. BrowserIsolator periodically synchronizes current Chrome DevTools Protocol page targets, so newly opened tabs are injected too. This is lightweight variation, not full device simulation.

Running environments cannot switch this mode because it affects Chrome launch arguments and CDP usage. Close the environment, change the setting, then start it again.

### Does video playback work?

Yes. The app uses official Google Chrome, so mainstream video sites and common codecs work normally.

### Does Chrome update automatically?

No. To update Chrome manually, use **Settings -> Redownload Chrome** first. All environments must be stopped and must not be starting or closing.

You can also delete:

```text
~/Library/Application Support/BrowserIsolator/Chromium/
```

The next launch downloads Chrome again.

### Does BrowserIsolator update automatically?

It supports in-app update checks. Use Check for Updates from the menu bar or **Settings -> About & Support**. BrowserIsolator uses Sparkle to check GitHub Releases for new app versions. Homebrew distribution is intentionally deferred for now to avoid mixing multiple update owners for the same installed app.

### How do I open links from other apps in a specific environment?

Open **Settings -> External Links**, choose the environment under Open in, then click Set as Default Browser. After that, http/https links opened from mail, chat apps, notes, and other apps are routed to the selected environment.

If the browser environment is not ready yet, or if no usable environment exists, BrowserIsolator shows a prompt instead of silently dropping the link and lets you copy the URL. When no environment is available, it can also open the main panel.

### How many environments can run at once?

There is no hard limit. Running no more than five at once is recommended, depending on memory, CPU, and the pages open in each environment.
