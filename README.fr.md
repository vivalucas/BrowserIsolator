# Isolateur de navigateur (BrowserIsolator)

Exécutez plusieurs environnements Chrome isolés sur un même Mac. Chaque environnement possède ses propres cookies, LocalStorage, mots de passe et sessions, ce qui facilite l'utilisation de plusieurs comptes sans se reconnecter sans cesse.

[中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator a un objectif précis : isoler proprement les environnements de navigateur en local. Ce n'est pas une plateforme anti-détection complète et il ne promet pas de contourner les systèmes de contrôle des sites.

## Fonctionnalités

- **Environnements isolés** : chaque environnement utilise son propre dossier de données Chrome
- **Contrôle rapide** : démarrer, fermer ou tout fermer depuis le panneau principal ou la barre de menus ; la fermeture attend que Chrome quitte
- **Informations d'environnement** : état, dossier, port de débogage, espace disque et dernière utilisation
- **Noms personnalisés** : renommer les environnements depuis le menu contextuel
- **Variation d'empreinte** : valeurs différentes pour `navigator.hardwareConcurrency` et `navigator.deviceMemory`, y compris dans les nouveaux onglets
- **Installation automatique du navigateur** : téléchargement de Google Chrome officiel au premier lancement
- **Local d'abord** : configuration et profils restent sur le Mac
- **7 langues** : 中文, English, 日本語, 한국어, Deutsch, Français, Русский

## Prérequis

- macOS 13 Ventura ou plus récent
- Mac Apple Silicon (M1 ou plus récent)

La version actuelle est construite pour `arm64-apple-macosx13.0` et ne prend pas en charge les Mac Intel.

## Installation

### Option 1 : télécharger le DMG

1. Téléchargez le dernier `BrowserIsolator.dmg` depuis [Releases](../../releases)
2. Ouvrez le DMG et déplacez `BrowserIsolator.app` dans Applications
3. Si macOS indique que le développeur ne peut pas être vérifié ou que l'app est endommagée :

   ```bash
   xattr -cr /Applications/BrowserIsolator.app
   ```

### Option 2 : compiler depuis le code source

Exécutable seul :

```bash
cd BrowserIsolator
swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx13.0
```

Application `.app` :

```bash
./build.sh
```

## Moteur de navigateur

BrowserIsolator utilise sa propre copie officielle de Google Chrome. Votre Chrome quotidien n'est ni lu ni modifié.

Emplacement :

```text
~/Library/Application Support/BrowserIsolator/Chromium/Google Chrome.app/
```

Si le téléchargement automatique échoue, téléchargez Google Chrome manuellement et placez `Google Chrome.app` dans `~/Library/Application Support/BrowserIsolator/Chromium/`.

## Utilisation

- **Démarrer** : cliquez sur Démarrer dans une ligne d'environnement ; une erreur s'affiche en cas d'échec
- **Fermer** : cliquez sur Fermer pour un environnement en cours ; l'état Fermeture reste affiché jusqu'à la sortie de Chrome
- **Tout fermer** : utilisez Tout fermer dans la barre d'outils
- **Ajouter** : cliquez sur Ajouter un environnement
- **Renommer / Supprimer** : clic droit sur un environnement ; la suppression n'est appliquée qu'après suppression réussie du dossier de données
- **Langue** : menu globe dans la barre d'outils ou la barre de menus

## Emplacement des données

```text
~/Library/Application Support/BrowserIsolator/
├── config.json
├── Chromium/
└── Profiles/
```

Pour tout supprimer, effacez ce dossier `BrowserIsolator`.

## FAQ

### Pourquoi ne pas utiliser Chrome déjà installé ?

Pour ne pas toucher à votre navigateur quotidien. BrowserIsolator utilise sa propre copie de Chrome et ses propres profils.

### Est-ce que cela évite les blocages de compte ?

Non garanti. BrowserIsolator fournit une isolation locale et une légère variation d'empreinte, mais ne promet pas de contourner la détection.

### Que fait la variation d'empreinte ?

Chrome DevTools Protocol définit `navigator.hardwareConcurrency` et `navigator.deviceMemory` par environnement. BrowserIsolator synchronise régulièrement les page targets actuelles, donc les nouveaux onglets sont aussi injectés. Ce n'est pas une simulation complète d'appareil.

### Chrome se met-il à jour automatiquement ?

Non. Pour le mettre à jour, supprimez `~/Library/Application Support/BrowserIsolator/Chromium/` puis relancez l'app.
