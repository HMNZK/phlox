# Third-Party Notices

Phlox is distributed under the MIT License (see `LICENSE`). It bundles and
depends on the following third-party components, each under its own license.
The copyright notices below are retained as required by those licenses.

## Vendored source

- **SwiftTerm** — MIT License. Copyright (c) Miguel de Icaza and contributors;
  portions derived from xterm.js (Copyright (c) The xterm.js authors,
  SourceLair Private Company) and blessed (Copyright (c) Christopher Jeffrey).
  Located under `macos/Vendor/SwiftTerm`. Contains local modifications.

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
