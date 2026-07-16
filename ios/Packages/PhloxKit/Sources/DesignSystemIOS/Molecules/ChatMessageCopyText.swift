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
}
