---
status: active
last-verified: 2026-10-20
---

# Tailscale向けAd Hoc配布物を準備する

登録済みiPhone向けに、アプリとWidgetを同じApple Developerチームで署名し、IPA・manifest・インストールページを作る。HTTPS配信とOTAインストール・起動を確認した。既存Mac Releaseでは接続失敗が発生したが、今回の隔離Debugでは実機接続に成功した。既存Releaseへの修正反映、別LAN・モバイル回線での確認、更新は未実施。

## 方針

`project.yml`からXcodeGenで生成し、標準のarchive/exportを使う。Team IDを明示し、過去の実機版build 1より大きいビルド番号を指定する。出力先は毎回新しく作り、既存配布物を上書きしない。配信するのは出力先の`public/`だけで、archive・ログ・署名資料は配信しない。

本体とWidgetのInfo.plistの`CFBundleVersion`は`CURRENT_PROJECT_VERSION`を参照させる。archive直後に両方の実ビルド番号を検査し、指定と異なる場合はexport前に停止する。マーケティング版は今回変更しない。

Tailscale Serveはこのスクリプトで変更しない。既存サービス、HTTPSの設定と配布用URLを確認し、追加する内容を本人が確認してから配信を設定する。Funnelは使わない。

## 作成する

必要なものはXcode・XcodeGen・Python 3と、アプリ/Widget両方のAd Hocプロファイル、Apple Distribution証明書の秘密鍵。プロファイルには配布先iPhone、App Groups、本体のPush Notificationsを含める。スクリプトはアカウントや登録端末を自動変更しない。署名資材が不足したら停止する。

リポジトリルートで、確認済みチームと配布URLを明示する。例のホスト名は実際のTailscaleホスト名へ置き換える。

```sh
python3 ios/scripts/prepare-ad-hoc.py \
  --team-id 9JGGMW6UW6 \
  --base-url https://MAC.TAILNET.ts.net/phlox-ios/ \
  --build-number 2 \
  --app-version 1.0 \
  --output .verification/tailscale-ios-install-20261020/release-2
```

XcodeGenで生成後、Releaseを汎用iOS端末向けにarchiveし、`release-testing`（Ad Hoc）としてexportする。署名チーム・登録端末付き配布プロファイル・Widget同梱・ビルド番号・表示版を検査する。`--app-version`は実ビルド設定へ渡し、本体とWidgetの実Info.plistが一致することをarchive/export後に確認する。`public/`の3ファイルが配布対象。`RESULT.txt`に版とGit revision、`archive.log`/`export.log`にログを保存する。失敗した出力先は残し、再実行では別の新規出力先を使う。

本人がApple側の署名資材更新を許可した場合に限り、`--allow-provisioning-updates`を追加できる。これはarchive/exportに`-allowProvisioningUpdates`を渡し、Xcodeのログイン済みアカウントから証明書・App ID・プロファイルの作成/更新/取得を許す。既定では使わない。新しい端末の自動登録は行わない。

署名中にKeychainの許可画面が出た場合は、本人がMac上で内容を確認して許可する。パスワードをチャットへ送信しない。

## 配信する

今回のMacはTailscaleのsystem extension版のため、ディレクトリを直接Serveできない。`public/`専用のHTTPサーバーをループバックだけで起動し、Serveから転送する。配布中はMacを起動したままにし、HTTPプロセスも動かしておく。

`tailscale serve status`で既存設定と`/phlox-ios/`の空きを確認する。`lsof -nP -iTCP:8843 -sTCP:LISTEN`で例のローカルポートが未使用か確認する。使用中なら別の未使用ポートを選び、既存プロセスを停止しない。追加内容を本人が確認した後、専用パスだけを設定する。Funnelは使わない。

```sh
python3 - '/絶対パス/release-2/public' <<'PY'
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import sys

SimpleHTTPRequestHandler.extensions_map.update({
    '.plist': 'text/xml', '.ipa': 'application/octet-stream',
})
handler = partial(SimpleHTTPRequestHandler, directory=sys.argv[1])
ThreadingHTTPServer(('127.0.0.1', 8843), handler).serve_forever()
PY
```

別のターミナルで、このHTTPプロセスのPID・実行ファイル・配信ディレクトリを出力先の`OWNER.txt`へ記録してから実行する。

```sh
tailscale serve --bg --https=443 --set-path=/phlox-ios http://127.0.0.1:8843
tailscale serve status
```

初回に`Serve is not enabled`と有効化リンクが表示されたら、そのリンクをブラウザで開いてServeを有効にする。本人認証が必要な場合は本人が操作し、有効化後に配信設定を再確認する。個別の有効化リンクは公開資料へ記録しない。

HTTPSの`/phlox-ios/index.html`・`/phlox-ios/manifest.plist`・`/phlox-ios/PhloxMobile.ipa`が取得できることを確認する。manifestのContent-Typeは`text/xml`、IPAは`application/octet-stream`とする。特にServeが転送時に`/phlox-ios`を取り除き、HTTPサーバーのルートにあるファイルへ届くことを実際に確認する。archiveやexportディレクトリを配信対象に指定しない。

iPhoneを別LANまたはモバイル回線に切り替え、Tailscaleを接続する。Safariで配布URLを開き「Phloxをインストール」を押す。起動と表示版を確認する。既存データを保持するため、更新前にアプリを削除しない。

更新時はビルド番号を増やし、新規出力先へ作成・検査する。別の未使用ローカルポートで新版`public/`のHTTPサーバーを起動し、取得できることを確認してから、同じ`/phlox-ios`の転送先だけを新版ポートへ切り替える。HTTPSで新版を確認後、旧版のHTTPプロセスを下記の照合手順で停止する。同じ8843ポートを再利用する場合は、新版の作成・検査後に旧PIDを照合して停止し、新版サーバーを8843で起動して到達確認する。その入れ替え中は一時的に配信が止まる。

停止時はこの作業で追加したパスだけを外す。既存Serve全体のリセットや443全体の停止は行わない。

```sh
tailscale serve --https=443 --set-path=/phlox-ios http://127.0.0.1:8843 off
tailscale serve status
```

最後に`OWNER.txt`のHTTP PIDを`ps -p <PID> -o pid=,ppid=,command=`と`lsof -a -p <PID> -d txt`で照合する。今回起動したPythonの実行ファイル・ポート・配信先が一致する場合だけ`kill <PID>`で停止し、`ps`で終了を確認する。別セッションやユーザーのプロセスは停止しない。`--bg`のServe設定はHTTPプロセスが終了しても残るため、mountの解除とHTTP停止の両方が必要。

## 検証状況

2026-10-20に、修正後スクリプトを手元で実行し、チーム`9JGGMW6UW6`で`1.0 / build 2`の署名付きarchiveとAd Hoc exportが成功した。本体/Widget両方の署名・チーム・配布プロファイル・実ビルド番号を検査し、IPA・manifest・インストールページを作成できた。成果物の基点はGit revision `ccdc37a9`で、今回の未コミット変更7ファイルを含む。過去のbuild 1の成果物は配布対象にしない。

リポジトリに登録したPython単体テスト4件が成功した。raw-value lintも成功し、CLIのhelpと不正引数の拒否を確認した。archive/exportと署名済み実物の検査は手元での実行結果であり、自動回帰テストには登録していない。初回はAd Hocプロファイル不足で失敗したが、本人の許可後に署名資材を更新して解消した。

ローカルHTTPで配布3ファイルのGETがHTTP 200となり、取得物のハッシュ一致とブラウザでのインストールページ表示を確認した。標準HTTPサーバーがmanifestを`application/octet-stream`で返し、Apple案内のMIME設定と不一致だったため、上記起動例で`text/xml`を明示するよう修正した。修正後も3ファイルのGETがHTTP 200となり、Content-Typeがページ`text/html`・manifest`text/xml`・IPA`application/octet-stream`であることと、取得物のバイト数・ハッシュ一致を手元で確認した。実物は`1.0 / build 2`。

署名資材更新と配信開始は本人が許可し、Serve有効化も完了した。配信はtailnet内だけで、Funnelによる一般公開はしていない。`/phlox-ios`から専用HTTPサーバーへの転送を1本設定した。

HTTPSでも3ファイルのGETがHTTP 200となり、TLS証明書の通常検証、Content-Type・バイト数・ハッシュ・manifest内URL・実版`1.0 / build 2`の一致を確認した。ブラウザでHTTPSページのタイトル・版・インストールリンクも確認した。両Ad Hocプロファイルに対象iPhone 14 Plusが含まれ、署名とプロファイルのApp Groupsが一致し、本体のPush Notificationsがproductionであることも確認した。これらは手元での検査。

本人からOTAインストール・起動成功の報告を得た。同じWi-Fiで最新QRを使用した際、既存Mac Releaseでは接続先の保存後に`GET /sessions`が無応答となった。その後、今回の隔離Debugへ実機接続できたと本人が報告し、Mac側でも端末の「ペアリング・接続中」表示を確認した。既存Releaseへの修正反映は未実施。別LAN・モバイル回線での利用と更新は未検証。

参照: [Appleの登録端末向け配布](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)、[Ad Hocプロファイル作成](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/)、[AppleのHTTP配信設定](https://support.apple.com/guide/deployment/distribute-proprietary-in-house-apps-depce7cefc4d/web)、[Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve)。
