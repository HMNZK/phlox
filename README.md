# Phlox

Phlox is a macOS app for running and orchestrating AI coding agents — Claude
Code, Codex, and Cursor — from a single native workspace, with a companion iOS
app for monitoring and steering your sessions remotely.

- **Multi-agent workspace** — spawn and manage many agent sessions side by side
  (terminal sessions and a structured chat mode), each in its own PTY.
- **Structured chat** — a native chat UI over supported CLIs, with tool-call and
  sub-agent visibility, approval gates, and per-turn cost/usage.
- **Grid & dashboard** — arrange sessions, track status, and follow completions.
- **Mobile companion** — an iOS app to watch sessions, receive push
  notifications, and answer prompts remotely over a private network.

This repository is a monorepo containing both apps.

## Repository layout

```
macos/   — the macOS app (SwiftUI + SwiftPM packages, generated with XcodeGen)
ios/     — the iOS companion app (SwiftUI + PhloxKit, generated with XcodeGen)
site/    — the project website and privacy policy (served at phlox.cc)
```

The iOS app reuses shared Swift packages from the macOS app (`AgentDomain`,
`DesignSystem`) via in-repo path dependencies.

## Requirements

- macOS 14+ and Xcode 16+ (Swift 6).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`.
  The `.xcodeproj` files are generated from `project.yml` and are not committed.
- At least one supported agent CLI installed for the macOS app to drive
  (e.g. Claude Code, Codex, or Cursor).
- **For the iOS companion:** a private overlay network between your Mac and
  phone. Phlox is designed around [Tailscale](https://tailscale.com/) — install
  the Tailscale app on both devices and join the same tailnet. Phlox does not
  bundle Tailscale; it connects over the tailnet you provide. iOS 17+.

## Building

### macOS app

```bash
cd macos
xcodegen generate
open Phlox.xcodeproj   # then build/run the "Phlox" scheme in Xcode
```

Run the package tests without building the app:

```bash
cd macos/Packages/<PackageName> && swift test
```

### iOS app

```bash
cd ios
xcodegen generate
open PhloxMobile.xcodeproj   # build/run on a simulator or device
```

## Code signing

The tracked `project.yml` files ship with an **empty `DEVELOPMENT_TEAM`**, so
the repository carries no personal signing identity. To build for a device or
to distribute, set your own Apple Developer Team ID — either in Xcode's
"Signing & Capabilities" tab, or via a local `Signing.local.xcconfig` (see
`Signing.example.xcconfig`). Simulator and local test builds need no team.

## License

Phlox is released under the [MIT License](LICENSE). Bundled third-party
components and trademarks are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Phlox is an independent project and is not affiliated with OpenAI, Anthropic,
Anysphere, or Tailscale; their names and marks are used only to indicate
compatibility.

## Contributing

Issues and pull requests are welcome. There is no support guarantee — this is
provided as-is under the MIT License.
