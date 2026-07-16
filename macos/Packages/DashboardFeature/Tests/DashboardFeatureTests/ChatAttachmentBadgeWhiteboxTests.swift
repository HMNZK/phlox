import Foundation
import Testing
@testable import SessionFeature

@Test
func chatAttachmentBadge_usesFilenameWhenPresent() throws {
    let badge = try #require(ChatAttachmentBadgePresentation(attachments: [
        ChatUserAttachment(filename: "shot.png", mediaType: "image/png"),
    ]))

    #expect(badge.title == "shot.png")
}

@Test
func chatAttachmentBadge_usesFallbackNameWhenFilenameIsMissing() throws {
    let badge = try #require(ChatAttachmentBadgePresentation(attachments: [
        ChatUserAttachment(filename: nil, mediaType: "image/jpeg"),
    ]))

    #expect(badge.title == "画像")
}

@Test
func chatAttachmentBadge_appendsCountWhenMultipleAttachmentsExist() throws {
    let badge = try #require(ChatAttachmentBadgePresentation(attachments: [
        ChatUserAttachment(filename: "first.png", mediaType: "image/png"),
        ChatUserAttachment(filename: "second.jpg", mediaType: "image/jpeg"),
    ]))

    #expect(badge.title == "first.png ×2")
}

@Test
func chatUserMessagePresentation_hidesTextWhenImageOnlySendHasEmptyText() {
    let presentation = ChatUserMessagePresentation(text: "", attachments: [
        ChatUserAttachment(filename: "shot.png", mediaType: "image/png"),
    ])

    #expect(presentation.showsText == false)
    #expect(presentation.badge?.title == "shot.png")
}

@Test
func chatUserMessagePresentation_showsTextAndBadgeWhenBothExist() {
    let presentation = ChatUserMessagePresentation(text: "見て", attachments: [
        ChatUserAttachment(filename: nil, mediaType: "image/png"),
    ])

    #expect(presentation.showsText == true)
    #expect(presentation.badge?.title == "画像")
}
