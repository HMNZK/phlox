# 外部操作を待つUI検証

外部操作が必要なUI検査は `ios/scripts/run-interactive-verification.py` から起動する。出力先は作業ごとの新規ディレクトリにし、既存の出力先を再利用しない。runnerはテストログをファイルへ送り、入れ子のready JSONを検知したらstep・instruction・ackFile・呼び出し側指定の期限・対象識別情報を標準出力へ即時表示する。

操作担当者は表示されたnonce、UDID、windowTitleを照合し、指定された画面だけを操作する。同名操作が通常アプリとfixtureの両方に出る場合は、fresh AXで選ぶbuttonの近傍と対象fixtureの位置関係を見分けてから押す。操作直後にfreshなfull AX rawとcapturedAtを採取し、ready JSONと同じackFileへ、nonce・scene・step・pid・udid・windowTitle・phase=`reviewed`・confirmed=`true`・capturedAt・rawAXTreeを含むJSONを保存する。自動ACK、期限変更、期待条件の緩和は禁止。対象が一致しない場合は続行せず失敗として扱う。

runnerは起動PIDとargv、ログ、出力先、終了コードをOWNER/STATUS JSONへ保存し、失敗時に再試行しない。readyやACKの内容を詳しく解析してから操作する運用を避け、表示された指示にすぐ対応する。UI操作が成立しなければ証拠と失敗を残して停止する。
