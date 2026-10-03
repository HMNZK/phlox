#!/usr/bin/env python3
"""選択中の Xcode build が、実行記録に基づく許可リストにあるか照合する。"""
import pathlib
import re
import subprocess
import sys


POLICY = (pathlib.Path(__file__).resolve().parents[1] /
          "Packages/DashboardFeature/Sources/DashboardFeature/Simulator/SimulatorPolicy.swift")


def main():
    try:
        result = subprocess.run(
            ["xcodebuild", "-version"], check=True, capture_output=True, text=True
        )
        build = re.search(r"^Build version (\S+)\s*$", result.stdout, re.MULTILINE)
        if build is None:
            raise ValueError("xcodebuild -version から build を取得できません")
        source = re.sub(r"/\*.*?\*/|//[^\n]*", "", POLICY.read_text(), flags=re.DOTALL)
        verified = re.search(
            r"static\s+let\s+verified\s*=\s*SimulatorPolicy\(entries:\s*\[(.*?)\]\)",
            source, re.DOTALL
        )
        if verified is None:
            raise ValueError("SimulatorPolicy.verified の許可リストを読み取れません")
        entries = re.findall(
            r'Entry\(\s*xcodeBuild:\s*"([^"]+)"\s*,\s*runtimeIdentifier:\s*"([^"]+)"'
            r'\s*,\s*supportsInput:\s*(?:true|false)\s*\)', verified.group(1)
        )
        runtimes = [runtime for entry_build, runtime in entries if entry_build == build.group(1)]
        if not runtimes:
            raise ValueError(f"Xcode build {build.group(1)} は許可リストにありません。実行記録を確認してください")
        print(f"許可リスト照合成功: Xcode build {build.group(1)} / {', '.join(runtimes)}")
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"許可リスト照合失敗: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
