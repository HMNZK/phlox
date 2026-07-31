import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// チャットメッセージの長押しコピー（クリップボード書き込みと contextMenu 付与）。
public enum ChatMessageCopyAction {
  public static func copyToPasteboard(_ text: String) {
    #if canImport(UIKit)
    UIPasteboard.general.string = text
    #elseif canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
  }
}

/// コピー文字列の遅延生成。連結が高コストな行（コマンド群・差分）で、
/// メニューが選ばれるまで生成しないために値ではなくクロージャを保持する。
public struct ChatMessageDeferredCopyText {
  private let provider: () -> String?

  public init(_ provider: @escaping () -> String?) {
    self.provider = provider
  }

  public func value() -> String? {
    provider()
  }
}

extension View {
  /// `copyText` が非 nil のとき、長押し contextMenu で「コピー」を出す。
  @ViewBuilder
  public func chatMessageCopyContextMenu(copyText: String?) -> some View {
    if let copyText {
      contextMenu {
        Button {
          ChatMessageCopyAction.copyToPasteboard(copyText)
        } label: {
          Label("コピー", systemImage: "doc.on.doc")
        }
      }
    } else {
      self
    }
  }

  /// コピー文字列の生成が高コストな行向け。`hasCopyableText` で可否だけを判定し、
  /// 実際の連結はメニューが選ばれるまで行わない。
  @ViewBuilder
  public func chatMessageCopyContextMenu(
    hasCopyableText: Bool,
    deferredCopyText: ChatMessageDeferredCopyText
  ) -> some View {
    if hasCopyableText {
      contextMenu {
        Button {
          guard let text = deferredCopyText.value() else { return }
          ChatMessageCopyAction.copyToPasteboard(text)
        } label: {
          Label("コピー", systemImage: "doc.on.doc")
        }
      }
    } else {
      self
    }
  }
}
