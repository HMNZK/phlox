---
status: accepted
---

# 0182: ブラウザはファイルプレビューと分け、非永続の子タブで開く

## 決定

- ChildTab.browser を追加する。タブごとに WKWebsiteDataStore.nonPersistent() を使用し、URL とタブ配置を保存しない。保存コピーだけを正規化し旧版との互換性を保つ。
- JavaScript と外部通信を有効にする。CDN のスライド等を閲覧するため、ユーザーが明示して開いたページとそのリソース・遷移を対象にする。初期ページを自動読み込みしない。
- ローカルファイルは loadFileURL で読み、許可は明示的に開いたファイルの親フォルダに限定する。範囲内の移動では許可を保つ。許可外へ移動するには URL 欄から明示的に開く。
- 戻る・進むでは既に開いた WebKit の履歴項目へ移動する。移動先が今の許可範囲内なら範囲を保ち、範囲外のファイルならその親フォルダに切り替える。
- 許可の変更は主フレームの didCommit で反映し、http/https の確定時に解除する。確定前の失敗・中止では表示中のページの許可を保つ。HTTP iframe を含む外部ページから file へのリンク・window.open・target=_blank は拒否し、明示的に開く操作と既に開いた履歴への移動だけを許可する。
- target=_blank/window.open は同じタブで開く。標準パネルで JavaScript の対話とファイル選択を扱う。アプリ内機能へのスクリプトの橋渡しは設けない。
- ADR 0178 はファイルプレビューの方針として維持する。ブラウザ入口は保存済みファイルを開く。
- 本体の sandbox は無効なのでネットワーク entitlement の追加は不要。署名設定・凍結テストは変更しない。
- HTTP を閲覧できるよう NSAllowsArbitraryLoadsInWebContent を有効にする。WebView にだけ適用し、URLSession の HTTPS 保護は維持する（[Apple の設定仕様](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent)）。ファイルプレビューの外部遮断ルールは維持する。
  NSAllowsArbitraryLoadsInWebContent はアプリ内のすべての WebView に効くが、ファイルプレビューは content rule list で外部通信を止めているため影響しない。

## 理由

安全なプレビューの制限を緩めると、選択しただけの HTML が外部通信やスクリプトを実行する。ブラウザを明示的に開く操作を別に設け、データを保存しないことで用途と寿命を明確にする。

## 結果

ログインはタブを閉じると消える。JavaScript を許可したページは、許可フォルダの参照と外部通信を行える。非永続のデータストアは外部送信を防ぐ機構ではない。閲覧だけを安全に行いたい HTML には既存のファイルプレビューを使う。履歴は開いている間の戻る／進むだけ。詳細は [仕様](../specs/in-app-browser.md)。

## 追記（2026-10-06）: 既定のブラウザ・検索・倍率・開発者ツール・エージェントに伝える

ユーザー判断で、HTML を常にブラウザで開く案は棄却し（編集中の内容がその場で表示されなくなり、信用できない HTML のスクリプトが同じフォルダを読めるため）、ブラウザ側の機能を広げる。保存するデータは増やさない（ログインの保持・複数タブは見送り）。`isInspectable` を有効にして Web インスペクタを使えるようにする。インスペクタは表示中のページを調べるだけで、許可範囲・データストア・外部通信の範囲を変えない。⌘F はメニューに置かず WebView が受ける（ファイルのエディタの ⌘F を奪わないため）。詳細は仕様の FR-7〜FR-11。
