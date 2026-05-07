# ブラウザ分離 (BrowserIsolator)

1 台の Mac で複数の独立した Chrome 環境を同時に実行できます。各環境は Cookie、LocalStorage、パスワード、ログイン状態を個別に保持するため、複数アカウントを扱うときに毎回ログインし直す必要がありません。

[中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator の目的はシンプルです。ローカルのブラウザ環境をきれいに分離すること。複雑な反検出ツールではなく、サイトのリスク制御を回避することも保証しません。日常的な複数アカウント運用を安定させるための軽量ツールです。

## 機能

- **独立環境**：環境ごとに別々の Chrome データディレクトリを使用
- **ワンクリック操作**：メインパネルまたはメニューバーから起動・終了
- **環境情報表示**：状態、フォルダ、デバッグポート、容量、最終使用日時を表示
- **名前変更**：環境に分かりやすい名前を付けられます
- **指紋差異化**：`navigator.hardwareConcurrency` と `navigator.deviceMemory` を環境ごとに変更
- **ブラウザ自動インストール**：初回起動時に公式 Google Chrome を自動ダウンロード
- **ローカル保存**：設定、Chrome、環境データはすべて Mac 内に保存
- **7 言語対応**：中文、English、日本語、한국어、Deutsch、Français、Русский

## 動作環境

- macOS 26 Tahoe 以降
- Apple Silicon Mac（M1 以降）

現在のリリースは `arm64-apple-macosx26.0` 向けで、Intel Mac には対応していません。

## インストール

### 方法 1：DMG をダウンロード

1. [Releases](../../releases) から最新の `BrowserIsolator.dmg` をダウンロード
2. DMG を開き、`BrowserIsolator.app` を Applications にドラッグ
3. 初回起動時に「開発元を確認できない」または「アプリが破損している」と表示された場合は、以下を実行してください：

   ```bash
   xattr -cr /Applications/BrowserIsolator.app
   ```

### 方法 2：ソースからビルド

実行ファイルだけを作る場合：

```bash
cd BrowserIsolator
swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx26.0
```

`.app` を作る場合：

```bash
./build.sh
```

## ブラウザエンジン

BrowserIsolator は独立した公式 Google Chrome を使用します。普段使っている Chrome の設定は読み取らず、変更もしません。

保存先：

```text
~/Library/Application Support/BrowserIsolator/Chromium/Google Chrome.app/
```

自動ダウンロードに失敗した場合は、Google Chrome を手動でダウンロードし、`Google Chrome.app` を `~/Library/Application Support/BrowserIsolator/Chromium/` に配置してください。

## 使い方

- **起動**：環境行の「起動」をクリック
- **終了**：実行中の環境で「閉じる」をクリック
- **すべて閉じる**：ツールバーの「すべて閉じる」
- **追加**：ツールバーの「環境を追加」
- **名前変更 / 削除**：環境を右クリック
- **言語切替**：ツールバーまたはメニューバーの地球アイコン

## データ保存場所

```text
~/Library/Application Support/BrowserIsolator/
├── config.json
├── Chromium/
└── Profiles/
```

完全に削除したい場合は、この `BrowserIsolator` フォルダを削除してください。

## FAQ

### 既存の Chrome を使わない理由は？

普段使いのブラウザを汚さないためです。BrowserIsolator は独自の Chrome と profile を使います。

### アカウント停止を防げますか？

保証できません。本プロジェクトはローカル分離と軽量な指紋差異化を目的としており、検出回避を約束するものではありません。

### 指紋差異化とは？

Chrome DevTools Protocol で `navigator.hardwareConcurrency` と `navigator.deviceMemory` を環境ごとに設定します。完全なデバイス模擬ではありません。

### Chrome は自動更新されますか？

されません。更新したい場合は `~/Library/Application Support/BrowserIsolator/Chromium/` を削除してから再起動してください。
