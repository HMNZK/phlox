import Foundation
import SwiftUI
import DesignSystem

struct FileLinkDestination: Equatable {
    let url: URL
    let decision: HTMLNavigationPolicy.Decision

    var path: String {
        guard let relativePath = WorktreeURL.relativePath(url) else { return url.absoluteString }
        let original = URLComponents(url: url, resolvingAgainstBaseURL: true)
        var components = URLComponents()
        components.percentEncodedQuery = original?.percentEncodedQuery
        components.percentEncodedFragment = original?.percentEncodedFragment
        return relativePath + (components.string ?? "")
    }

    var icon: String {
        switch decision {
        case .openFile: "doc"
        case .openBrowser: "arrow.up.right"
        case .allow: "arrow.down"
        case .cancel: "nosign"
        }
    }
}

struct FileLinkDestinationView: View {
    let destination: FileLinkDestination

    var body: some View {
        HStack(spacing: DSSpacing.chip) {
            Image(systemName: destination.icon)
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityHidden(true)
            Text(destination.decision.destinationLabel)
                .font(DSFont.caption.weight(.semibold))
                .fixedSize()
                .accessibilityLabel("\(destination.decision.destinationLabel)  \(destination.path)")
            Text(destination.path)
                .font(DSFont.monoCaption)
                .foregroundStyle(DSColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityHidden(true)
        }
        .font(DSFont.caption)
        .foregroundStyle(DSColor.textPrimary)
        .padding(.horizontal, DSSpacing.s)
        .frame(height: DSSpacing.xl)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.row))
        .overlay(RoundedRectangle(cornerRadius: DSRadius.row).stroke(DSColor.border, lineWidth: 0.5))
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: DSSpacing.chip, y: DSSpacing.xs)
        .allowsHitTesting(false)
    }
}
