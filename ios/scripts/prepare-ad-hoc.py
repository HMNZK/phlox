#!/usr/bin/env python3
"""標準XcodeツールでAd Hoc配布物を新規ディレクトリへ作る。"""

import argparse
import html
import plistlib
from pathlib import Path
import re
import shutil
import subprocess
import os
from urllib.parse import quote, urlsplit, urlunsplit
import zipfile


def base_url(value):
    url = urlsplit(value)
    if (url.scheme != "https" or not url.hostname
            or not url.hostname.endswith(".ts.net") or url.username or url.password
            or url.port not in (None, 443) or url.query or url.fragment
            or not re.fullmatch(r"[a-zA-Z0-9.-]+", url.hostname)
            or any(part in (".", "..") for part in url.path.split("/"))
            or "%" in url.path):
        raise ValueError("base URLにはTailscaleのHTTPS URLを指定してください（認証情報・query・fragment不可）")
    return urlunsplit(("https", url.netloc, quote(url.path.rstrip("/") + "/", safe="/"), "", ""))


def write_install_files(ipa, public, url):
    with zipfile.ZipFile(ipa) as archive:
        apps = [name for name in archive.namelist()
                if re.fullmatch(r"Payload/[^/]+\.app/Info.plist", name)]
        if len(apps) != 1:
            raise ValueError("IPAにアプリが1個必要です")
        prefix = apps[0].removesuffix("Info.plist")
        widgets = [name for name in archive.namelist()
                   if name.startswith(prefix + "PlugIns/") and name.endswith(".appex/Info.plist")]
        if len(widgets) != 1:
            raise ValueError("IPAにWidgetが1個必要です")
        info = plistlib.loads(archive.read(apps[0]))
        widget = plistlib.loads(archive.read(widgets[0]))
        if (info["CFBundleIdentifier"] != "com.phlox.mobile.PhloxMobile"
                or widget["CFBundleIdentifier"] != "com.phlox.mobile.PhloxMobile.PhloxWidget"
                or info["CFBundleVersion"] != widget["CFBundleVersion"]):
            raise ValueError("アプリとWidgetの識別子またはビルド番号が不一致です")
    manifest = {"items": [{"assets": [{"kind": "software-package", "url": url + quote(ipa.name)}],
                            "metadata": {"bundle-identifier": info["CFBundleIdentifier"],
                                         "bundle-version": info["CFBundleVersion"],
                                         "kind": "software", "title": "Phlox"}}]}
    with (public / "manifest.plist").open("wb") as file:
        plistlib.dump(manifest, file)
    install_url = "itms-services://?action=download-manifest&url=" + quote(url + "manifest.plist", safe="")
    (public / "index.html").write_text(
        '<!doctype html><html lang="ja"><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>Phloxをインストール</title><h1>Phlox</h1>'
        f'<p>{html.escape(info["CFBundleShortVersionString"])} / build {html.escape(info["CFBundleVersion"])}</p>'
        f'<p><a href="{html.escape(install_url, quote=True)}">Phloxをインストール</a></p>'
        '<p>登録済みiPhoneのSafariで開いてください。更新前にアプリを削除しないでください。</p></html>',
        encoding="utf-8")
    return info


def run(command, **kwargs):
    subprocess.run(command, check=True, **kwargs)


def verify_signatures(app, team):
    widgets = list((app / "PlugIns").glob("*.appex"))
    if len(widgets) != 1:
        raise ValueError("署名検査対象のWidgetが1個必要です")
    for bundle in [app, *widgets]:
        run(["codesign", "--verify", "--strict", str(bundle)])
        result = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(bundle)],
                                check=True, capture_output=True)
        entitlements = plistlib.loads(result.stdout)
        profile = plistlib.loads(subprocess.check_output(
            ["security", "cms", "-D", "-i", str(bundle / "embedded.mobileprovision")]))
        if (entitlements.get("com.apple.developer.team-identifier") != team
                or entitlements.get("get-task-allow") is not False
                or profile.get("TeamIdentifier") != [team]
                or profile["Entitlements"].get("get-task-allow") is not False
                or not profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices")):
            raise ValueError(f"Ad Hoc署名・チーム・登録端末を確認できません: {bundle.name}")


def verify_build_number(app, build_number, app_version):
    widgets = list((app / "PlugIns").glob("*.appex"))
    if len(widgets) != 1:
        raise ValueError("ビルド番号検査対象のWidgetが1個必要です")
    for bundle in [app, *widgets]:
        with (bundle / "Info.plist").open("rb") as file:
            info = plistlib.load(file)
        if info.get("CFBundleVersion") != str(build_number):
            raise ValueError(f"ビルド番号が指定の{build_number}と異なります: {bundle.name}")
        if info.get("CFBundleShortVersionString") != app_version:
            raise ValueError(f"表示版が指定の{app_version}と異なります: {bundle.name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--base-url", required=True, help="https://host.tailnet.ts.net/phlox-ios/")
    parser.add_argument("--build-number", required=True, type=int)
    parser.add_argument("--app-version", required=True, help="アプリ本体とWidgetで照合する表示版")
    parser.add_argument("--output", required=True, type=Path, help="存在しない出力ディレクトリ")
    parser.add_argument("--allow-provisioning-updates", action="store_true",
                        help="本人が許可した場合のみ: XcodeによるApple側の署名資材更新を許可")
    args = parser.parse_args()
    try:
        url = base_url(args.base_url)
        if (not re.fullmatch(r"[A-Z0-9]{10}", args.team_id) or args.build_number <= 1
                or not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", args.app_version)):
            raise ValueError("Team IDは10桁の英数字、build numberは2以上、表示版は数値をドットで区切って指定してください")
        for command in ("xcodegen", "xcodebuild", "codesign", "security", "ditto"):
            if not shutil.which(command):
                raise ValueError(f"必要なコマンドがありません: {command}")
        output = args.output.resolve()
        output.mkdir(parents=True, exist_ok=False)
        (output / "OWNER.txt").write_text(
            f"用途: iOS Ad Hoc配布物。作成: prepare-ad-hoc.py PID {os.getpid()}\n"
            f"出力先: {output}\n常駐プロセス: なし。配信対象はpublicのみ。\n", encoding="utf-8")
        ios = Path(__file__).resolve().parents[1]
        provisioning = ["-allowProvisioningUpdates"] if args.allow_provisioning_updates else []
        run(["xcodegen", "generate"], cwd=ios)
        archive = output / "PhloxMobile.xcarchive"
        with (output / "archive.log").open("w") as log:
            run(["xcodebuild", "archive", "-project", str(ios / "PhloxMobile.xcodeproj"),
                 "-scheme", "PhloxMobile", "-configuration", "Release",
                 "-destination", "generic/platform=iOS", "-archivePath", str(archive),
                 "-derivedDataPath", str(output / "build"), f"DEVELOPMENT_TEAM={args.team_id}",
                 f"CURRENT_PROJECT_VERSION={args.build_number}", f"MARKETING_VERSION={args.app_version}", "CODE_SIGN_STYLE=Automatic", *provisioning],
                stdout=log, stderr=subprocess.STDOUT)
        archive_apps = list((archive / "Products/Applications").glob("*.app"))
        if len(archive_apps) != 1:
            raise ValueError("archiveにアプリが1個必要です")
        verify_build_number(archive_apps[0], args.build_number, args.app_version)
        options = output / "ExportOptions.plist"
        with options.open("wb") as file:
            plistlib.dump({"method": "release-testing", "teamID": args.team_id,
                           "signingStyle": "automatic", "signingCertificate": "Apple Distribution",
                           "manageAppVersionAndBuildNumber": False}, file)
        with (output / "export.log").open("w") as log:
            run(["xcodebuild", "-exportArchive", "-archivePath", str(archive),
                 "-exportPath", str(output / "export"), "-exportOptionsPlist", str(options), *provisioning],
                stdout=log, stderr=subprocess.STDOUT)
        ipas = list((output / "export").glob("*.ipa"))
        if len(ipas) != 1:
            raise ValueError("書き出されたIPAが1個必要です")
        inspection = output / "inspection"
        run(["ditto", "-x", "-k", str(ipas[0]), str(inspection)])
        apps = list((inspection / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise ValueError("署名検査対象のアプリが1個必要です")
        verify_build_number(apps[0], args.build_number, args.app_version)
        verify_signatures(apps[0], args.team_id)
        public = output / "public"
        public.mkdir()
        ipa = public / "PhloxMobile.ipa"
        shutil.copy2(ipas[0], ipa)
        info = write_install_files(ipa, public, url)
        if info["CFBundleVersion"] != str(args.build_number):
            raise ValueError("書き出したビルド番号が指定と異なります")
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ios, text=True).strip()
        status = subprocess.check_output(["git", "status", "--short"], cwd=ios, text=True)
        (output / "RESULT.txt").write_text(
            f"revision: {revision}\nteam: {args.team_id}\n"
            f"version: {info['CFBundleShortVersionString']}\nbuild: {info['CFBundleVersion']}\n"
            f"配信ディレクトリ: {public}\nURL: {url}\n遠隔iPhoneインストール: 未検証\n"
            f"作業ツリー（空なら変更なし）:\n{status}", encoding="utf-8")
        print(f"配布物: {public}\n配信設定は未変更です。URL: {url}")
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"失敗: {error}\n出力先のarchive.log/export.logを確認してください。既存配信は未変更です。\n")


if __name__ == "__main__":
    main()
