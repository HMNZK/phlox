#if DEBUG
import SwiftUI

/// E2-2 トークンの目視確認用 Preview。Dynamic Type フォント・スペーシング・アイコンを一覧表示する。
struct DSTokensPreviewView: View {
    private let icons: [(String, String)] = [
        ("sessions", DSIcon.sessions),
        ("spawn", DSIcon.spawn),
        ("send", DSIcon.send),
        ("reachable", DSIcon.reachable),
        ("unreachable", DSIcon.unreachable),
        ("faceID", DSIcon.faceID),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                Group {
                    Text("title1").font(DSFont.title1)
                    Text("title2").font(DSFont.title2)
                    Text("headline").font(DSFont.headline)
                    Text("body").font(DSFont.body)
                    Text("subheadline").font(DSFont.subheadline)
                    Text("footnote").font(DSFont.footnote)
                }

                Divider()

                HStack(spacing: DSSpacing.m) {
                    ForEach(icons, id: \.1) { label, symbol in
                        VStack(spacing: DSSpacing.xs) {
                            Image(systemName: symbol)
                                .frame(width: DSTouch.minSize, height: DSTouch.minSize)
                            Text(label).font(DSFont.footnote)
                        }
                    }
                }

                Text("minTouch = \(Int(DSTouch.minSize))pt")
                    .font(DSFont.caption)
            }
            .padding(DSSpacing.l)
        }
    }
}

#Preview("DS Tokens") {
    DSTokensPreviewView()
}
#endif
