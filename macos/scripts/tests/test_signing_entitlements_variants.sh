#!/usr/bin/env bash
# task-5 の受け入れテスト（PM が凍結・実装役は編集不可）。
#
# 固定する契約:
#   1. 証明書を持たない環境の既定 entitlements に keychain-access-groups が入らないこと。
#      （入ると、それを認可するプロビジョニングプロファイルが無いため AMFI がアプリを
#        起動時に SIGKILL する＝外部貢献者のビルドが起動しなくなる。docs/phase0.md 2.4）
#   2. Data Protection Keychain 用の entitlements が別ファイルとして存在し、そちらには入っていること。
#   3. 切り替えが Signing.xcconfig の変数 1 箇所で行われること（project.yml に直値を書かない）。
#   4. DPK 構成で実際にビルドでき、生成された .app に embedded.provisionprofile と
#      keychain-access-groups の両方が入ること。
#
# 使い方: bash macos/scripts/tests/test_signing_entitlements_variants.sh
# 環境変数 SKIP_BUILD=1 で 4 のビルド検査だけを飛ばせる（構造検査 1〜3 は必ず走る）。
#
# 失敗は握りつぶさない。エラーを 2>/dev/null や || true で隠さないこと。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # = <repo>/macos
PROJECT_ROOT="$(cd "$REPO_ROOT/.." && pwd)"

PLAIN_ENTITLEMENTS="$REPO_ROOT/App/Phlox.entitlements"
DPK_ENTITLEMENTS="$REPO_ROOT/App/Phlox-DataProtectionKeychain.entitlements"
SIGNING_XCCONFIG="$REPO_ROOT/Config/Signing.xcconfig"
PROJECT_YML="$REPO_ROOT/project.yml"

failures=0
pass() { printf '  ok   %s\n' "$1"; }
fail() { printf '  FAIL %s\n' "$1"; failures=$((failures + 1)); }

echo "== 1. 既定の entitlements に keychain-access-groups が無いこと =="
if [ ! -f "$PLAIN_ENTITLEMENTS" ]; then
  fail "既定の entitlements が見つからない: $PLAIN_ENTITLEMENTS"
elif grep -q "keychain-access-groups" "$PLAIN_ENTITLEMENTS"; then
  fail "既定の entitlements に keychain-access-groups が混入している（ad-hoc ビルドが起動しなくなる）"
else
  pass "既定の entitlements は現行のまま"
fi

echo "== 2. DPK 用の entitlements が存在し keychain-access-groups を持つこと =="
if [ ! -f "$DPK_ENTITLEMENTS" ]; then
  fail "DPK 用の entitlements が見つからない: $DPK_ENTITLEMENTS"
else
  if grep -q "keychain-access-groups" "$DPK_ENTITLEMENTS"; then
    pass "DPK 用の entitlements に keychain-access-groups がある"
  else
    fail "DPK 用の entitlements に keychain-access-groups が無い"
  fi
  # app-sandbox の値が既定側と食い違っていないこと（2 ファイルに分けたことによる乖離の検出）。
  plain_sandbox="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$PLAIN_ENTITLEMENTS")"
  dpk_sandbox="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$DPK_ENTITLEMENTS")"
  if [ "$plain_sandbox" = "$dpk_sandbox" ]; then
    pass "app-sandbox の値が 2 ファイルで一致している ($plain_sandbox)"
  else
    fail "app-sandbox が食い違っている（既定=$plain_sandbox / DPK=$dpk_sandbox）"
  fi
fi

echo "== 3. 切り替えが Signing.xcconfig の変数 1 箇所で行われること =="
if grep -qE '^[[:space:]]*PHLOX_CODE_SIGN_ENTITLEMENTS[[:space:]]*=' "$SIGNING_XCCONFIG"; then
  pass "Signing.xcconfig に PHLOX_CODE_SIGN_ENTITLEMENTS がある"
else
  fail "Signing.xcconfig に PHLOX_CODE_SIGN_ENTITLEMENTS が無い"
fi
if grep -qE '^[[:space:]]*PHLOX_CODE_SIGN_ENTITLEMENTS[[:space:]]*=[[:space:]]*App/Phlox\.entitlements[[:space:]]*$' "$SIGNING_XCCONFIG"; then
  pass "既定値が非 DPK 版になっている"
else
  fail "PHLOX_CODE_SIGN_ENTITLEMENTS の既定値が App/Phlox.entitlements ではない"
fi
if grep -qE 'CODE_SIGN_ENTITLEMENTS:[[:space:]]*"?\$\(PHLOX_CODE_SIGN_ENTITLEMENTS\)"?' "$PROJECT_YML"; then
  pass "project.yml が変数から引いている"
else
  fail "project.yml の CODE_SIGN_ENTITLEMENTS が変数経由になっていない（直値のハードコード）"
fi
if grep -qE 'keychain-access-groups' "$PROJECT_YML"; then
  fail "project.yml に keychain-access-groups が直書きされている（正本の二重化）"
else
  pass "project.yml に entitlement の直書きが無い"
fi

echo "== 4. DPK 構成で実際にビルドでき、成果物に profile と entitlement が入ること =="
if [ "${SKIP_BUILD:-0}" = "1" ]; then
  echo "  SKIP  SKIP_BUILD=1 のためビルド検査を実行していない（未検証）"
else
  # 「ファイルが無い」と「あるが読めない」を区別する。後者を SKIP に丸めると、
  # 検査していないことを「証明書の無い環境だから」と誤って説明してしまう。
  local_xcconfig="$PROJECT_ROOT/Signing.local.xcconfig"
  if [ ! -e "$local_xcconfig" ]; then
    team=""
  elif [ ! -r "$local_xcconfig" ]; then
    fail "Signing.local.xcconfig が読めない（権限を確認すること）: $local_xcconfig"
    team=""
  else
    # grep の exit code を区別する: 0=一致、1=一致なし（正常）、2 以上=エラー。
    # `|| true` でまとめて吸収すると、エラーまで「チーム ID なし」に化けて検査が黙って SKIP になる。
    set +e
    team_line="$(grep -hE '^[[:space:]]*PHLOX_DEVELOPMENT_TEAM[[:space:]]*=' "$local_xcconfig" | tail -1)"
    grep_status=${PIPESTATUS[0]}
    set -e
    if [ "$grep_status" -gt 1 ]; then
      fail "Signing.local.xcconfig の読み取りに失敗した（grep exit=$grep_status）: $local_xcconfig"
      team=""
    else
      team="$(printf '%s' "$team_line" | sed 's/.*=[[:space:]]*//' | tr -d '[:space:]')"
    fi
  fi
  if [ -z "$team" ]; then
    echo "  SKIP  Signing.local.xcconfig にチーム ID が無い環境のためビルド検査を実行していない（未検証）"
  else
    dd="$(mktemp -d)/DD"
    app="$dd/Build/Products/Debug/Phlox.app"
    echo "  building (derivedDataPath=$dd) ..."
    xcodebuild \
      -project "$REPO_ROOT/Phlox.xcodeproj" \
      -scheme Phlox \
      -configuration Debug \
      -derivedDataPath "$dd" \
      -allowProvisioningUpdates \
      PHLOX_CODE_SIGN_ENTITLEMENTS=App/Phlox-DataProtectionKeychain.entitlements \
      build > "$dd.log" 2>&1 || {
        echo "  --- 末尾 40 行 ---"; tail -40 "$dd.log"; fail "DPK 構成のビルドに失敗した"; }

    if [ -d "$app" ]; then
      if [ -f "$app/Contents/embedded.provisionprofile" ]; then
        pass "embedded.provisionprofile が埋め込まれている"
      else
        fail "embedded.provisionprofile が無い（DPK は動作しない）"
      fi
      if codesign -d --entitlements - "$app" 2>&1 | grep -q "keychain-access-groups"; then
        pass "署名済み entitlements に keychain-access-groups がある"
      else
        fail "署名済み entitlements に keychain-access-groups が無い"
      fi
    else
      fail "ビルド成果物が見つからない: $app"
    fi
  fi
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "PASS: すべての検査に合格"
  exit 0
fi
echo "FAIL: $failures 件の検査に失敗"
exit 1
