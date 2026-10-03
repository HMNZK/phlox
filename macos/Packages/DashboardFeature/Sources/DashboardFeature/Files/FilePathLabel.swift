import AppKit
import DesignSystem
import SwiftUI

/// 先頭のフォルダから省略し、ファイル名の途中では切らない。
enum FilePathDisplay {
    static func minimumReadableWidth(_ path: String, font: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)) -> CGFloat {
        let components = path.split(separator: "/").map(String.init)
        let suffix = components.count > 2 ? "…/" + components.suffix(2).joined(separator: "/") : path
        return ceil((suffix as NSString).size(withAttributes: [.font: font]).width)
    }

    static func abbreviated(_ path: String, width: CGFloat, font: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)) -> String {
        func fits(_ text: String) -> Bool { (text as NSString).size(withAttributes: [.font: font]).width <= width }
        if fits(path) { return path }
        let components = path.split(separator: "/").map(String.init)
        guard components.count > 1 else { return path }
        for index in 1..<max(1, components.count) {
            let suffix = "…/" + components[index...].joined(separator: "/")
            if fits(suffix) { return suffix }
        }
        return components.last.map { "…/" + $0 } ?? path
    }

    static func homeRelative(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

struct FilePathLabel: View {
    let path: String

    var body: some View {
        GeometryReader { geometry in
            Text(verbatim: FilePathDisplay.abbreviated(path, width: geometry.size.width))
                .font(DSFont.monoCaption)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
                .help(path)
                .accessibilityLabel(Text(verbatim: path))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 20)
    }
}
