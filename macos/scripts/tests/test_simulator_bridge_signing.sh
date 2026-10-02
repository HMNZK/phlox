#!/usr/bin/env bash
# 生成済みアプリの XPC 同梱・署名・権限・本体への非公開リンク混入を検査する。
set -euo pipefail
MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="${1:-$MACOS_DIR/../.build/DerivedData/Build/Products/Debug/Phlox.app}"
python3 - "$MACOS_DIR" "$APP" <<'PY'
import pathlib
import plistlib
import subprocess
import sys
import unittest

root = pathlib.Path(sys.argv[1])
app = pathlib.Path(sys.argv[2])
sys.argv = [sys.argv[0]]

def plist(path):
    return plistlib.loads(path.read_bytes())

def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result

class 署名検査(unittest.TestCase):
    def test_専用権限を使い本体の権限を継承しない(self):
        source = plist(root / "SimulatorBridgeService/SimulatorBridgeService.entitlements")
        self.assertNotIn("com.apple.security.cs.disable-library-validation", source)
        self.assertNotIn("keychain-access-groups", source)
        self.assertFalse(source.get("com.apple.security.app-sandbox", False))
        project = (root / "project.yml").read_text()
        self.assertIn("CODE_SIGN_ENTITLEMENTS: SimulatorBridgeService/SimulatorBridgeService.entitlements", project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.phlox.Phlox.debug.SimulatorBridge", project)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER: com.phlox.Phlox.SimulatorBridge", project)

    def test_XPCを同梱しflavorと版が一致する(self):
        host = plist(app / "Contents/Info.plist")
        services = list((app / "Contents/XPCServices").glob("*.xpc"))
        self.assertEqual(len(services), 1)
        service = plist(services[0] / "Contents/Info.plist")
        self.assertEqual(service["CFBundleIdentifier"], host["CFBundleIdentifier"] + ".SimulatorBridge")
        self.assertEqual(service["CFBundleVersion"], host["CFBundleVersion"])
        self.assertEqual(service["CFBundleShortVersionString"], host["CFBundleShortVersionString"])
        self.assertEqual(service["XPCService"]["ServiceType"], "Application")

    def test_両署名とhardenedRuntimeと実際の権限(self):
        services = list((app / "Contents/XPCServices").glob("*.xpc"))
        self.assertEqual(len(services), 1)
        teams = []
        for bundle in [app, services[0]]:
            run("codesign", "--verify", "--strict", str(bundle))
            signature = run("codesign", "--display", "--verbose=4", str(bundle)).stderr
            team = next(line for line in signature.splitlines() if line.startswith("TeamIdentifier="))
            if bundle != app or team != "TeamIdentifier=not set":
                self.assertIn("runtime", signature)
            teams.append(team)
            data = run("codesign", "--display", "--entitlements", "-", "--xml", str(bundle)).stdout
            entitlements = plistlib.loads(data.encode()) if data.strip() else {}
            self.assertNotIn("com.apple.security.cs.disable-library-validation", entitlements)
            if bundle != app:
                self.assertNotIn("keychain-access-groups", entitlements)
                self.assertFalse(entitlements.get("com.apple.security.app-sandbox", False))
        self.assertEqual(teams[0], teams[1])

    def test_本体に非公開フレームワークをリンクしない(self):
        binaries = []
        helper_text = ""
        for path in (app / "Contents").rglob("*"):
            if not path.is_file():
                continue
            if "Mach-O" not in run("file", "-b", str(path)).stdout:
                continue
            text = run("otool", "-L", str(path)).stdout + run("strings", "-a", str(path)).stdout
            if "XPCServices" in path.relative_to(app / "Contents").parts:
                helper_text += text
                continue
            binaries.append(path)
            for framework in ["CoreSimulator.framework", "SimulatorKit.framework"]:
                self.assertNotIn(framework, text, str(path))
        self.assertTrue(binaries, "本体の Mach-O が見つかりません")
        if plist(app / "Contents/Info.plist")["CFBundleIdentifier"].endswith(".debug"):
            self.assertTrue(any(path.name.endswith(".debug.dylib") for path in binaries),
                            "Debug の実体が検査対象に含まれていません")
        for framework in ["CoreSimulator.framework", "SimulatorKit.framework"]:
            self.assertIn(framework, helper_text, "対照の XPC サービスで検出できません")

unittest.main(verbosity=2)
PY
