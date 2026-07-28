import Foundation
import Testing

/// 端末描画の「高さは中身が決める」という配線を凍結する（→ ADR 0037）。
///
/// 高さの決め方は View の配線そのもので、値型のテストでは表現できない。固定高さや端末
/// エミュレータへ戻しても、パーサのテストは全部 green のまま画面だけが切れる（実際にそれで
/// 「上半分しか表示されない」不具合を出した）。ここで配線を文字列として縛る。
@Suite("端末描画の配線")
struct TerminalScreenWiringTests {

    @Test("高さは中身が要求する分をそのまま使う（固定しない）")
    func heightComesFromTheContent() throws {
        let source = try sourceText("Sources/TerminalScreenIOS/TerminalScreenView.swift")

        #expect(source.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(
            !source.contains("height: layout.height"),
            "算出した固定高さへ嵌め直さないこと（枠より高い中身が切れる）"
        )
    }

    @Test("端末エミュレータ（固定行数の格子とスクロールバック）を挟まない")
    func doesNotEmbedATerminalEmulator() throws {
        let source = try sourceText("Sources/TerminalScreenIOS/TerminalScreenView.swift")

        #expect(!source.contains("import SwiftTerm"))
        #expect(!source.contains("UIViewRepresentable"))
    }

    @Test("高さの下限は地の色を伸ばすだけで、中身の高さは縛らない")
    func minimumHeightOnlyExtendsTheBackground() throws {
        let source = try sourceText("Sources/TerminalScreenIOS/TerminalScreenView.swift")

        #expect(source.contains("minHeight: minimumHeight"))
        #expect(!source.contains("maxHeight: minimumHeight"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
