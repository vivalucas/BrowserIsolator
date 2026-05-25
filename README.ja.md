# ブラウザ分離 (BrowserIsolator)

1 台の Mac で複数の独立した Chrome 環境を同時に実行できます。各環境は Cookie、LocalStorage、パスワード、ログイン状態を個別に保持するため、複数アカウントを扱うときに毎回ログインし直す必要がありません。

[中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Русский](README.ru.md)

BrowserIsolator の目的はシンプルです。ローカルのブラウザ環境をきれいに分離すること。複雑な反検出ツールではなく、サイトのリスク制御を回避することも保証しません。日常的な複数アカウント運用を安定させるための軽量ツールです。

## 機能

- **独立環境**：環境ごとに別々の Chrome データディレクトリを使用
- **ワンクリック操作**：メインパネルまたはメニューバーから起動・終了し、終了時は Chrome の終了を待ちます
- **環境情報表示**：状態、フォルダ、実行モード、容量、最終使用日時を表示。デバッグポートは必要な場合のみ詳細情報に表示
- **名前とメモ**：環境に分かりやすい名前や短いメモを付けられます
- **基本モード優先**：既定では profile データだけを分離し、デバッグポートやページスクリプト注入は使いません
- **任意の差分モード**：設定で環境ごとに有効化できます。有効な環境は次回起動時に `navigator.hardwareConcurrency` と `navigator.deviceMemory` を注入します
- **外部リンク**：BrowserIsolator を既定のブラウザにし、他のアプリから開いたリンクを指定した環境に送れます
- **ブラウザ自動インストール**：初回起動時に公式 Google Chrome を自動ダウンロード
- **アプリ内更新**：Sparkle で GitHub Releases の新しいバージョンを確認
- **ローカル保存**：設定、Chrome、環境データはすべて Mac 内に保存
- **7 言語対応**：中文、English、日本語、한국어、Deutsch、Français、Русский

## 動作環境

- macOS 13 Ventura 以降
- Apple Silicon Mac（M1 以降）

現在のリリースは `arm64-apple-macosx13.0` 向けで、Intel Mac には対応していません。

## インストール

### 方法 1：DMG をダウンロード

1. [Releases](../../releases) から最新の `BrowserIsolator.dmg` をダウンロード
2. DMG を開き、`BrowserIsolator.app` を Applications にドラッグ
3. 初回起動時に「開発元を確認できない」または「アプリが破損している」と表示された場合は、以下を実行してください：

   ```bash
   xattr -cr /Applications/BrowserIsolator.app
   ```

以後の更新は **設定 -> 情報とサポート -> アップデート確認** から確認できます。初回インストールは引き続き Releases の DMG が必要です。

### 方法 2：ソースからビルド

実行ファイルだけを作る場合：

```bash
cd BrowserIsolator
swift build -c release -Xswiftc -target -Xswiftc arm64-apple-macosx13.0
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

- **起動**：環境行の「起動」をクリック。失敗した場合はエラーが表示されます
- **終了**：実行中の環境で「閉じる」をクリック。Chrome が終了するまで「終了中」と表示されます
- **すべて閉じる**：ツールバーの「すべて閉じる」
- **追加**：ツールバーの「環境を追加」
- **名前変更 / メモ / 削除**：環境を右クリック、または右側の詳細欄から操作できます。削除時は確認後にデータをゴミ箱へ移動します
- **外部リンク**：**設定 -> 外部リンク** で開き先の環境を選び、BrowserIsolator を既定のブラウザに設定できます
- **設定**：Chrome の状態、データフォルダ、外観、言語、更新、作者情報、フィードバックを確認できます
- **差分モード**：設定で環境ごとに有効化できます。実行中の環境は変更できないため、閉じてから変更し、次回起動で反映します
- **言語切替**：ツールバーまたはメニューバーの地球アイコン

## データ保存場所

```text
~/Library/Application Support/BrowserIsolator/
├── config.json          # 環境、名前、メモ
├── Chromium/
└── Profiles/
```

完全に削除したい場合は、この `BrowserIsolator` フォルダを削除してください。

## FAQ

### 既存の Chrome を使わない理由は？

普段使いのブラウザを汚さないためです。BrowserIsolator は独自の Chrome と profile を使います。

### アカウント停止を防げますか？

保証できません。本プロジェクトはローカル分離を中心に、必要に応じた軽量な指紋差異化を提供します。検出回避を約束するものではありません。

### 差分モードとは？

既定では何も注入しません。BrowserIsolator は基本モードを優先し、ローカル profile データだけを分離します。

設定で差分モードを有効にした環境は、次回起動時に Chrome DevTools Protocol で `navigator.hardwareConcurrency` と `navigator.deviceMemory` を環境ごとに設定します。現在の page target を定期的に同期するため、新しく開いたタブにも注入されます。完全なデバイス模擬ではありません。

このモードは Chrome の起動引数と CDP 利用に関わるため、実行中の環境では切り替えられません。

### Chrome は自動更新されますか？

されません。更新したい場合は `~/Library/Application Support/BrowserIsolator/Chromium/` を削除してから再起動してください。

### BrowserIsolator は自動更新されますか？

アプリ内で更新確認できます。メニューバーの「アップデート確認」、または **設定 -> 情報とサポート** を使ってください。更新確認には Sparkle と GitHub Releases を使います。

### 他のアプリから開いたリンクを特定の環境で開くには？

**設定 -> 外部リンク** で開き先の環境を選び、「既定のブラウザにする」をクリックします。メール、チャット、メモなどから開いた http/https リンクが選択した環境に送られます。環境がまだ準備できていない場合は、リンクをコピーできる確認画面を表示します。
