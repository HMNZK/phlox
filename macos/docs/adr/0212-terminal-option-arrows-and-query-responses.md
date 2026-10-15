---
status: accepted
last-verified: 2026-10-15
---

# ADR 0212: Option＋左右矢印を限定して割り当て、端末応答の要求を区別する

## 文脈

TerminalCoordinator は日本語入力を守るため `optionAsMetaKey = false` としている。その結果、SwiftTerm の Option＋左右矢印の ESC b／f 変換にも入らない。大量の色付き出力後に `1!~000065;4;1;2;6;21;22;17;28c` に似た入力が一度観測されたが、元ファイル・生成スクリプトは残っていない。

## 決定

- 共通の IMETerminalView で、Kitty キーボードプロトコルが無効（`keyboardEnhancementFlags.isEmpty`）のときだけ Option 単独＋左右矢印を ESC b／f に変換する。通常／アプリケーションカーソルモードの両方に適用する。Shift・Control・Command の組合せや IME 未確定中は既存処理を維持する。全 Option 文字をメタキーにする設定は採用しない。
- Kitty が有効なときは、左右矢印の Option 修飾を保持して既存の Kitty 符号化に渡す。`>1u` では押下とリピートを送り、解放は要求されない。`>3u`・`>7u` では押下・リピート・解放を送る。変換の押下記録と解放の消費は行わない。
- 端末応答をシェルの状態で捨てない。問い合わせへの正当な応答と誤応答を、入力バイトを固定した Swift Testing で区別する。元ファイルがないため、元の事故を再現・解決したとは報告しない。
- SwiftTerm の `cmdDECRQCRA` は中間文字を検査せず、問い合わせでない `CSI 1y` にもチェックサム応答を返す。失敗する回帰テストを先に作り、必要な `*` を確認する局所修正を行う。SGR の解析は再現なしに変更しない。

要求に `*` が必要なことは [xterm の制御シーケンス仕様](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)の DECRQCRA と一致する。問い合わせを含まない合成40万行の試験では応答は発生せず、元の観測がこの検査漏れによるものかは未確定である。

## 理由と結果

SwiftTerm の keyDown は外部からオーバーライドできない。公開APIを増やさず、共通ビューが継承する既存の keyDown に限定割り当てを置く。

下部端末とエージェント端末で同じキー操作となり、Option での文字入力を保つ。操作部品・文言・PTYKit の変更は不要。

2026-10-15 に [SwiftTerm 上流 main の Terminal.swift](https://github.com/migueldeicaza/SwiftTerm/blob/main/Sources/SwiftTerm/Terminal.swift) の `cmdDECRQCRA` を確認し、同じ中間文字の検査欠落が残っていた。上流修正の移植ではなく手元の局所修正として TerminalUI/Package.swift に記録する。上流 EscapeSequenceParser はパラメータの表現も異なり、一括更新は行わない。

Ghostty の [現行の既定設定](https://github.com/ghostty-org/ghostty/blob/main/src/config/Config.zig)（Keybinds.init の macOS natural text editing）を参照する。Shift などの追加修飾を単語移動に拡張せず、Option 単独の既定割り当てに範囲を限定する。

検証結果・未確認範囲は architecture/terminal-editor-panels.md に記録する。

上流の MacTerminalView には `optionAsMetaKeyForFunctionalKeys` と AppKit の単語移動セレクタへの対応がある。ただし機能キー全般と Kitty の入力経路も変わっているため、左右矢印だけを要求する本件では一括移植せず、既存の ESC b／f 定数を再利用する。

## 2026-10-15 レビュー後の補足

上流を再照合したコミットは [`8230eb751ec124bd8c2a7d7643566c51cd5ea763`](https://github.com/migueldeicaza/SwiftTerm/blob/8230eb751ec124bd8c2a7d7643566c51cd5ea763/Sources/SwiftTerm/Terminal.swift)。この固定版の `cmdDECRQCRA` にも中間文字の検査がないことを確認した。先の main 参照の確認対象を、再照合できる SHA として記録する。

レビューで、押下記録がフォーカス移動で残る経路と、通常矢印の長押し途中で Option を加えると Kitty の解放を消費する経路が判明した。記録の補修は採用せず、従来モードの各イベントだけで変換を判断する方針へ改稿する。従来モードは解放を送らないため、記録も解放の消費も不要となる。Kitty では各イベントの現在の修飾キーをそのまま符号化する。ADR 0213 の描画方式と端末応答の修正は変更しない。

正当な応答の期待値は手元の `cmdSendDeviceAttributes`・`cmdDeviceStatus` と [xterm 仕様](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)を照合する。DA2 は手元が識別する VT525／版20／PCキーボードの `CSI >65;20;1c`、DSR は正常状態 `CSI 0n` と初期カーソル位置 `CSI 1;1R`、DECCKSR は要求ID 7 を保持する `DCS 7!~0000 ST`。DA2 の版番号は xterm 自身の値ではなく SwiftTerm の値であり、DECCKSR のゼロは手元の未実装マクロの応答である。各問い合わせの全バイト境界での分割受信も回帰テストに追加する。
