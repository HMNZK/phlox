---
status: active
last-verified: 2026-07-10
---

# ADR 0063: @ファイル補完は TCC 保護フォルダを「実パス一致」で除外する

> **このファイルの役割**: Phlox が写真/ダウンロード/ミュージック等へのアクセス権を要求していた原因（@補完の再帰列挙）と、除外を名前一致でなくパス一致にした決定理由。
> **書かないもの**: 補完の実装詳細（→ Packages/SessionFeature/Sources/SessionFeature/ComposerSuggestions.swift）。

## 文脈

Phlox 使用中に macOS の TCC ダイアログ（ダウンロード・写真・ミュージックフォルダへのアクセス許可）が出ることがあった。原因はコンポーザの `@` ファイル補完（`ComposerSuggestionSources.collectFiles`）が作業ディレクトリ配下を深さ4まで `contentsOfDirectory` で再帰列挙し、除外が `.git/.build/node_modules/DerivedData` の名前一致のみで、ユーザーホーム配下の TCC 保護フォルダに降下しうること（コードベースで home 配下を再帰列挙するのはここだけ。PTY spawn は login shell 非経由で対策済み＝AgentLaunchPlanner）。

## 決定

- `fileCandidates` に defaulted 引数 `protectedDirectories: Set<String>` を追加。既定値 `defaultProtectedDirectories` は **ユーザードメインの Downloads/Pictures/Music/Desktop/Documents/Movies の実パス6つ**（`FileManager.urls(for:in:.userDomainMask)` で解決）。
- 再帰列挙中、子ディレクトリの**標準化絶対パスが保護集合に一致する場合のみ降下しない**（`contentsOfDirectory` を呼ばない。TCC はアクセス時に発火するため「列挙してから捨てる」は不可）。
- **ルート自体が保護フォルダの場合は走査する**（ユーザーが明示的に選んだ作業ディレクトリであり、その場合の TCC 要求は正当）。

## 棄却案

- **名前一致での除外**（excludedDirectoryNames に "Downloads" 等を追加）: プロジェクト内の同名の通常フォルダ（`<repo>/Downloads/` 等）まで補完から消える偽陽性。棄却。
- **ホーム直下を作業ディレクトリにすること自体の禁止**: ユーザーの正当なユースケースを塞ぐ。棄却。

## 結果

- 受け入れテスト AcceptanceProtectedFolderTests が凍結（パス一致・同名非保護は走査・ルート例外・既定集合）。
- 残余: ユーザーが保護フォルダ自体（またはそれを深さ4以内に含む場所）を作業ディレクトリに選んだ場合の TCC 要求は仕様どおり残る。修正後も別経路で再現する場合は再現手順の採取が必要（フェーズ0調査では他経路は検出されず）。
