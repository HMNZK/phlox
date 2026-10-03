# Third-Party Notices

Phlox is distributed under the MIT License (see `LICENSE`). It bundles and
depends on the following third-party components, each under its own license.
The copyright notices below are retained as required by those licenses.

## Vendored source

- **SwiftTerm** — MIT License. Copyright (c) Miguel de Icaza and contributors;
  portions derived from xterm.js (Copyright (c) The xterm.js authors,
  SourceLair Private Company) and blessed (Copyright (c) Christopher Jeffrey).
  Located under `macos/Vendor/SwiftTerm`. Contains local modifications.

## Ported source

- **thinking-orbs** — MIT License. Copyright (c) 2026 Jakub Antalik
  (<https://github.com/Jakubantalik/thinking-orbs>). The dotted thinking-orb
  rendering engine (six animation modes, density profiles and tuned presets)
  was ported from TypeScript/Canvas 2D to Swift/CoreGraphics. The Swift port
  lives under `macos/Packages/DesignSystem/Sources/DesignSystem/ThinkingOrb`
  and is used by both the macOS and iOS apps.

## Swift Package Manager dependencies

### macOS app (`macos/`)

| Package | License | Copyright |
|---|---|---|
| [NetworkImage](https://github.com/gonzalezreal/NetworkImage) | MIT | Guillermo Gonzalez |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | MIT-style (permissive) | Sparkle Project / Andy Matuschak |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 | Apple Inc. |
| [swift-cmark](https://github.com/swiftlang/swift-cmark) | BSD-2-Clause | John MacFarlane |
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | MIT | Guillermo Gonzalez |

### iOS app (`ios/`)

| Package | License | Copyright |
|---|---|---|
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | MIT | Guillermo Gonzalez |
| [NetworkImage](https://github.com/gonzalezreal/NetworkImage) | MIT | Guillermo Gonzalez |
| [swift-cmark](https://github.com/swiftlang/swift-cmark) | BSD-2-Clause | John MacFarlane |

The full Apache-2.0 text (for swift-argument-parser) is available at
<https://www.apache.org/licenses/LICENSE-2.0>. The BSD-2-Clause and MIT texts
are available in each project's repository.

## Trademarks

Phlox integrates with third-party AI coding CLIs and displays their brand
marks for identification purposes only. The following logos, bundled under
`macos/Packages/DesignSystem/.../Icons.xcassets` and used by both apps, are the
trademarks of their respective owners and are **not** covered by Phlox's MIT
License:

- **ChatGPT / OpenAI** logo — trademark of OpenAI.
- **Claude** logo — trademark of Anthropic.
- **Cursor** logo — trademark of Anysphere.

Likewise, **Tailscale** is a trademark of Tailscale Inc. Phlox is an
independent project and is not affiliated with, endorsed by, or sponsored by
any of these companies. Their marks are used solely to indicate compatibility.

# シミュレーターの試作と補助プロセス

`macos/Prototypes/SimulatorGate/Service/PrivateSimulatorAPI.m` および `macos/SimulatorBridgeService/PrivateSimulatorAPI.m` の非公開 API の宣言と入力・表示の呼び出し手順は、次の一次資料を参照して記述した。

- Meta idb（MIT、Copyright (c) Meta Platforms, Inc. and affiliates.）：`de8ab367691b826004af3d9cf9c0efc0e449e652` の `SimulatorIndigoHIDClient.swift`、`SimulatorIndigoHID.swift`、`PrivateHeaders`。
- Expo serve-sim（Apache-2.0、原著作権者 Evan Bacon）：`c91e75b3c81dfa9eea6faea0f99e1273383dd90e` の `FrameCapture.swift`、`HIDInjector.swift`。試作では変更通知で保持した surface の seed を観測し、接触の移動を押下として送る。

ライセンス原文と serve-sim の NOTICE は `macos/Prototypes/SimulatorGate/Licenses/` に保存した。
