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
  /// `copyText` が非 nil のとき、長押し contextMenu でコピーと部分選択を出す。
  @ViewBuilder
  public func chatMessageCopyContextMenu(
    copyText: String?,
    menuTitle: String? = nil,
    partialSelectionEnabled: Bool = false,
    onPartialSelection: (() -> Void)? = nil
  ) -> some View {
    if partialSelectionEnabled {
      self
    } else if let copyText {
      if let menuTitle {
        #if canImport(UIKit)
        background {
          ChatMessageCopyMenuInteraction(
            title: menuTitle,
            hasCopyableText: true,
            copyText: { copyText },
            onPartialSelection: onPartialSelection
          )
        }
        #else
        contextMenu {
          copyMenuItems(copyText: copyText, onPartialSelection: onPartialSelection)
        }
        #endif
      } else {
        contextMenu {
          copyMenuItems(copyText: copyText, onPartialSelection: onPartialSelection)
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
    deferredCopyText: ChatMessageDeferredCopyText,
    menuTitle: String? = nil,
    partialSelectionEnabled: Bool = false,
    onPartialSelection: (() -> Void)? = nil
  ) -> some View {
    if partialSelectionEnabled {
      self
    } else if hasCopyableText {
      if let menuTitle {
        #if canImport(UIKit)
        background {
          ChatMessageCopyMenuInteraction(
            title: menuTitle,
            hasCopyableText: hasCopyableText,
            copyText: { deferredCopyText.value() },
            onPartialSelection: onPartialSelection
          )
        }
        #else
        contextMenu {
          deferredCopyMenuItems(deferredCopyText, onPartialSelection: onPartialSelection)
        }
        #endif
      } else {
        contextMenu {
          deferredCopyMenuItems(deferredCopyText, onPartialSelection: onPartialSelection)
        }
      }
    } else {
      self
    }
  }

  @ViewBuilder
  private func copyMenuItems(copyText: String, onPartialSelection: (() -> Void)?) -> some View {
    Button {
      ChatMessageCopyAction.copyToPasteboard(copyText)
    } label: {
      Label("コピー", systemImage: "doc.on.doc")
    }
    if let onPartialSelection {
      Button("選択して部分コピー", action: onPartialSelection)
    }
  }

  @ViewBuilder
  private func deferredCopyMenuItems(
    _ deferredCopyText: ChatMessageDeferredCopyText,
    onPartialSelection: (() -> Void)?
  ) -> some View {
    Button {
      guard let text = deferredCopyText.value() else { return }
      ChatMessageCopyAction.copyToPasteboard(text)
    } label: {
      Label("コピー", systemImage: "doc.on.doc")
    }
    if let onPartialSelection {
      Button("選択して部分コピー", action: onPartialSelection)
    }
  }
}

#if canImport(UIKit)
private struct ChatMessageCopyMenuInteraction: UIViewRepresentable {
  let title: String
  let hasCopyableText: Bool
  let copyText: () -> String?
  let onPartialSelection: (() -> Void)?

  func makeCoordinator() -> Coordinator {
    Coordinator(
      title: title,
      hasCopyableText: hasCopyableText,
      copyText: copyText,
      onPartialSelection: onPartialSelection
    )
  }

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.backgroundColor = .clear
    view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {
    context.coordinator.update(
      title: title,
      hasCopyableText: hasCopyableText,
      copyText: copyText,
      onPartialSelection: onPartialSelection
    )
  }

  @MainActor
  final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
    private var title: String
    private var hasCopyableText: Bool
    private var copyText: () -> String?
    private var onPartialSelection: (() -> Void)?

    init(
      title: String,
      hasCopyableText: Bool,
      copyText: @escaping () -> String?,
      onPartialSelection: (() -> Void)?
    ) {
      self.title = title
      self.hasCopyableText = hasCopyableText
      self.copyText = copyText
      self.onPartialSelection = onPartialSelection
    }

    func update(
      title: String,
      hasCopyableText: Bool,
      copyText: @escaping () -> String?,
      onPartialSelection: (() -> Void)?
    ) {
      self.title = title
      self.hasCopyableText = hasCopyableText
      self.copyText = copyText
      self.onPartialSelection = onPartialSelection
    }

    func contextMenuInteraction(
      _ interaction: UIContextMenuInteraction,
      configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
      guard hasCopyableText else { return nil }
      return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
        guard let self else { return nil }
        var children: [UIMenuElement] = [
          UIAction(title: "コピー", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
            guard let text = self?.copyText() else { return }
            UIPasteboard.general.string = text
          },
        ]
        if let onPartialSelection = self.onPartialSelection {
          children.append(UIAction(title: "選択して部分コピー") { _ in onPartialSelection() })
        }
        return UIMenu(title: self.title, children: children)
      }
    }
  }
}
#endif
