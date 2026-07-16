# ADR 0003: Tailscale 接続の平文 HTTP とクライアント側認証ガード

## 状態

採用

## 文脈

Phlox-mobile は Tailscale を前提に Mac の Phlox プロキシへ平文 HTTP で接続する。接続先には MagicDNS 名だけでなく、Tailscale CGNAT アドレスやプライベート IP アドレスの直打ちも使われる。ATS 例外を名前付きホストへ限定する厳格化は、IP 直打ち接続を保全できず、既存の接続経路を壊す。

一方、接続先が誤設定された場合に Bearer トークンを平文で一般のホストへ送ることは避けなければならない。

## 判断

Tailscale 前提の平文 HTTP を許容し、クライアント側ガードで多層防御する。接続要求自体は従来どおり送るが、MagicDNS の `*.ts.net`、Tailscale CGNAT、RFC 1918 プライベートアドレス、loopback だけを信頼し、それ以外の host には Bearer トークンを付与しない。

ATS 例外限定による厳格化は採らない。MagicDNS に限定すると IP 直打ち接続を失うためである。

## 結果

信頼できる Tailscale・ローカル接続の既存挙動と IP 直打ち接続を維持しつつ、誤設定された一般ホストへの認証情報送信をクライアント側で防ぐ。平文 HTTP 自体は残るため、Tailscale の暗号化と接続先制御を前提とする。
