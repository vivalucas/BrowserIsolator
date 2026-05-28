# Isolateur de navigateur (BrowserIsolator)

Exécutez plusieurs environnements Chrome isolés sur un même Mac. Chaque environnement possède ses propres cookies, LocalStorage, mots de passe et sessions, ce qui facilite l'utilisation de plusieurs comptes sans se reconnecter sans cesse.

[中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator a un objectif précis : isoler proprement les environnements de navigateur en local. Ce n'est pas une plateforme anti-détection complète et il ne promet pas de contourner les systèmes de contrôle des sites.

## Fonctionnalités

- **Environnements isolés** : chaque environnement utilise son propre dossier de données Chrome
- **Contrôle rapide** : démarrer, fermer ou tout fermer depuis le panneau principal ou la barre de menus ; un second clic sur une ligne d'environnement sélectionnée la démarre, et la fermeture attend que Chrome quitte
- **Informations d'environnement** : la liste de gauche montre l'état, l'espace disque et la dernière utilisation ; le panneau de droite affiche le chemin du profil, le mode d'exécution, les erreurs, les actions et les détails avancés. Le port de débogage apparaît seulement au besoin dans les détails avancés
- **Noms et notes** : nommer les environnements et ajouter une courte note pour un compte, un client ou un usage
- **Suppression sûre** : la suppression demande de saisir le nom de l'environnement, puis déplace les données dans la corbeille
- **Mode de base par défaut** : seul le profil est isolé, sans port de débogage ni injection de script dans les pages
- **Mode variation optionnel** : activable par environnement dans les réglages ; les environnements activés injectent `navigator.hardwareConcurrency` et `navigator.deviceMemory` au prochain lancement
- **Liens externes** : définir BrowserIsolator comme navigateur par défaut et choisir l'environnement qui reçoit les liens ouverts depuis d'autres apps ; si aucune cible n'est disponible, l'app affiche une alerte au lieu de perdre le lien
- **Installation automatique du navigateur** : téléchargement de Google Chrome officiel au premier lancement
- **Réglages** : état et version de Chrome, dossiers de données, copie des chemins, nouveau téléchargement de Chrome, liens externes, langue, apparence, détails avancés, mises à jour, contact et retour
- **Récupération de configuration** : si `config.json` est corrompu ou illisible, BrowserIsolator charge les valeurs par défaut et tente de conserver le fichier défectueux
- **Local d'abord** : configuration, Chrome et profils restent sur le Mac ; BrowserIsolator ne téléverse ni ne collecte les données utilisateur
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

Les mises à jour suivantes se vérifient dans **Réglages -> À propos et aide -> Rechercher des mises à jour**. La première installation passe toujours par le DMG des Releases.

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

- **Démarrer** : cliquez sur Démarrer dans une ligne d'environnement, cliquez à nouveau sur la ligne sélectionnée ou utilisez le panneau de détails à droite ; une erreur s'affiche en cas d'échec
- **Fermer** : cliquez sur Fermer pour un environnement en cours ; l'état Fermeture reste affiché jusqu'à la sortie de Chrome
- **Tout fermer** : utilisez Tout fermer dans la barre d'outils
- **Ajouter** : cliquez sur Ajouter un environnement
- **Renommer / notes / supprimer** : clic droit sur un environnement ou panneau de détails à droite. La suppression déplace les données dans la corbeille
- **Liens externes** : dans **Réglages -> Liens externes**, choisissez l'environnement cible et définissez BrowserIsolator comme navigateur par défaut. Si l'environnement n'est pas encore prêt ou si aucun environnement utilisable n'existe, vous pouvez copier le lien ; lorsqu'aucun environnement n'est disponible, le panneau principal peut aussi être ouvert
- **Réglages** : état de Chrome, dossiers de données, copie des chemins, nouveau téléchargement de Chrome, apparence, langue, mises à jour, contact et liens de retour. Le nouveau téléchargement de Chrome n'est disponible que si aucun environnement ne démarre, n'est en cours ou ne se ferme
- **Mode variation** : activable par environnement dans les réglages. Les environnements en cours ne peuvent pas être modifiés ; fermez-les puis relancez-les
- **Langue** : menu globe dans la barre d'outils ou la barre de menus

## Emplacement des données

```text
~/Library/Application Support/BrowserIsolator/
├── config.json          # environnements, noms et notes
├── Chromium/
│   └── Google Chrome.app/
└── Profiles/
    ├── p1/
    ├── p2/
    └── p3/
```

Pour tout supprimer, effacez ce dossier `BrowserIsolator`.

Si `config.json` est corrompu ou ne peut pas être lu, BrowserIsolator affiche une alerte, charge la configuration par défaut et tente de conserver le fichier original sous `config.corrupt-<timestamp>.json`.

## FAQ

### Pourquoi ne pas utiliser Chrome déjà installé ?

Pour ne pas toucher à votre navigateur quotidien. BrowserIsolator utilise sa propre copie de Chrome et ses propres profils.

### Est-ce que cela évite les blocages de compte ?

Non garanti. BrowserIsolator se concentre sur l'isolation locale et propose un mode variation léger au besoin, mais ne promet pas de contourner la détection.

### Que fait le mode variation ?

Par défaut, rien n'est injecté. BrowserIsolator privilégie le mode de base et isole seulement les données locales du profil.

Si le mode variation est activé dans les réglages, le prochain lancement utilise Chrome DevTools Protocol pour définir `navigator.hardwareConcurrency` et `navigator.deviceMemory` par environnement. BrowserIsolator synchronise régulièrement les page targets actuelles, donc les nouveaux onglets sont aussi injectés. Ce n'est pas une simulation complète d'appareil.

Ce mode touche aux arguments de lancement de Chrome et à l'usage de CDP, il ne peut donc pas être modifié pendant qu'un environnement est en cours.

### Chrome se met-il à jour automatiquement ?

Non. Pour le mettre à jour, utilisez d'abord **Réglages -> Télécharger Chrome à nouveau**. Tous les environnements doivent être arrêtés et ne doivent pas être en démarrage ou en fermeture. Vous pouvez aussi supprimer `~/Library/Application Support/BrowserIsolator/Chromium/` puis relancer l'app.

### BrowserIsolator se met-il à jour automatiquement ?

L'app peut rechercher les mises à jour. Utilisez Rechercher des mises à jour dans la barre de menus ou **Réglages -> À propos et aide**. BrowserIsolator utilise Sparkle et GitHub Releases.

### Comment ouvrir les liens d'autres apps dans un environnement précis ?

Ouvrez **Réglages -> Liens externes**, choisissez l'environnement cible, puis cliquez sur Définir le navigateur par défaut. Les liens http/https ouverts depuis Mail, les apps de messagerie, les notes et d'autres apps seront envoyés vers cet environnement. Si l'environnement n'est pas encore prêt ou si aucun environnement utilisable n'existe, BrowserIsolator affiche une alerte et permet de copier le lien. Lorsqu'aucun environnement n'est disponible, le panneau principal peut aussi être ouvert.
