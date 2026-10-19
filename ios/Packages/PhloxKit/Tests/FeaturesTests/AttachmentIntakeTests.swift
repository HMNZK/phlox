import CoreGraphics
import Foundation
import ImageIO
import ImageAttachmentKit
import Testing
import UniformTypeIdentifiers
import PhloxCore
@testable import Features

@MainActor
@Suite("AC-6-18 添付の個別受理", .serialized)
struct AttachmentIntakeTests {
    enum Composer: CaseIterable, Sendable {
        case newChat, detail, detailPicker
    }

    // 同じ入力を新規・詳細の同期追加・Picker追加へ通す。
    @MainActor
    private struct Harness {
        let newChat: NewChatViewModel?
        let detail: SessionDetailViewModel?
        let composer: Composer

        init(_ composer: Composer) {
            self.composer = composer
            if composer == .newChat {
                newChat = NewChatViewModel(api: MockAPI(), entryProject: .init(project: ""))
                detail = nil
                newChat?.inputText = "本文"
                newChat?.inputCursorUTF16 = 2
            } else {
                newChat = nil
                detail = SessionDetailViewModel(session: Session(
                    id: "s1", name: "Rose", agent: .claudeCode, status: .idle,
                    subtitle: "proj", updatedAt: Date(timeIntervalSince1970: 0)
                ), api: MockAPI())
                detail?.inputText = "本文"
                detail?.inputCursorUTF16 = 2
            }
        }

        var items: [SessionDetailViewModel.SessionAttachmentItem] {
            newChat?.attachmentItems ?? detail!.attachmentItems
        }
        var text: String { newChat?.inputText ?? detail!.inputText }
        var cursor: Int { newChat?.inputCursorUTF16 ?? detail!.inputCursorUTF16 }
        var error: String? { newChat?.attachmentError ?? detail?.attachmentError }

        func add(_ images: [SendAttachment]) async {
            switch composer {
            case .newChat: await newChat!.addAttachments(images)
            case .detail: detail!.addAttachments(images)
            case .detailPicker: await detail!.addAttachmentsFromPicker(images)
            }
        }

        func addLoadResults(_ results: [Result<SendAttachment, Error>]) async {
            if let newChat {
                await newChat.addAttachmentLoadResults(results)
            } else {
                await detail!.addAttachmentLoadResults(results)
            }
        }
    }

    private func image(bytes: Int = 1024) -> SendAttachment {
        var data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")!
        data.append(Data(count: max(0, bytes - data.count)))
        return SendAttachment(mediaType: "image/png", data: data)
    }

    private var broken: SendAttachment { .init(mediaType: "image/png", data: Data([1, 2, 3])) }

    @Test(arguments: [Composer.newChat, .detailPicker])
    func pickerLoadFailureKeepsSuccessfulImagesAndFirstError(_ composer: Composer) async {
        let vm = Harness(composer)
        await vm.add([image()])
        let original = vm.items[0]
        let valid = image(bytes: 2048)
        let loaded = SendAttachment(mediaType: "application/octet-stream", data: valid.data)

        await vm.addLoadResults([
            .failure(URLError(.cannotDecodeContentData)),
            .success(loaded),
            .success(image(bytes: 20_000_001)),
            .success(loaded),
        ])

        #expect(vm.items.first == original)
        #expect(vm.items.map(\.send) == [original.send, valid, valid])
        #expect(vm.items.map(\.number) == [1, 2, 3])
        #expect(vm.items.allSatisfy { !$0.previewData.isEmpty })
        #expect(vm.text == "本文 [Image #1] [Image #2] [Image #3] ")
        #expect(vm.error == "画像を読み込めませんでした")
    }

    @Test(arguments: [Composer.newChat, .detailPicker])
    func pickerEarlierSizeErrorSurvivesLaterLoadFailure(_ composer: Composer) async {
        let vm = Harness(composer)
        let valid = image()
        await vm.addLoadResults([
            .success(image(bytes: 20_000_001)),
            .failure(URLError(.cannotLoadFromNetwork)),
            .success(valid),
        ])
        #expect(vm.items.map(\.send) == [valid])
        #expect(vm.items.map(\.number) == [1])
        #expect(vm.error == "画像は1枚あたり20MBまでです")
        #expect(vm.text == "本文 [Image #1] ")
    }

    @Test(arguments: [Composer.newChat, .detailPicker])
    func pickerEarlierDimensionErrorSurvivesLaterLoadFailure(_ composer: Composer) async throws {
        let vm = Harness(composer)
        let valid = image()
        await vm.addLoadResults([
            .success(try dimensionImage(width: 8001, height: 1)),
            .failure(URLError(.cannotDecodeContentData)),
            .success(valid),
        ])
        #expect(vm.items.map(\.send) == [valid])
        #expect(vm.error == "画像は各辺8000ピクセルまでです。必要な部分を切り出してください")
    }

    @Test(arguments: [Composer.newChat, .detailPicker])
    func pickerOnlyLoadFailuresPreserveExistingDraft(_ composer: Composer) async {
        let vm = Harness(composer)
        await vm.add([image()])
        let items = vm.items
        let text = vm.text
        let cursor = vm.cursor

        await vm.addLoadResults([.failure(ImageAttachmentPreparationError.invalidImage)])
        await vm.addLoadResults([])

        #expect(vm.items == items)
        #expect(vm.text == text)
        #expect(vm.cursor == cursor)
        #expect(vm.error == "画像を読み込めませんでした")
    }

    @Test(arguments: Composer.allCases)
    func mixedBatchPreservesExistingAndAcceptsValidInOrder(_ composer: Composer) async {
        let vm = Harness(composer)
        let existing = image(bytes: 512)
        await vm.add([existing])
        let existingItem = vm.items[0]
        let first = image(bytes: 1024)
        let second = image(bytes: 2048)
        await vm.add([first, image(bytes: 20_000_001), broken, second])

        #expect(vm.items.map(\.send) == [existing, first, second])
        #expect(vm.items.first == existingItem)
        #expect(vm.items.map(\.number) == [1, 2, 3])
        #expect(vm.items.allSatisfy { !$0.previewData.isEmpty })
        #expect(vm.text == "本文 [Image #1] [Image #2] [Image #3] ")
        #expect(vm.error == "画像は1枚あたり20MBまでです")
    }

    @Test(arguments: Composer.allCases)
    func brokenFirstDoesNotHideValidOrLaterErrors(_ composer: Composer) async {
        let vm = Harness(composer)
        let valid = image()
        await vm.add([broken, valid, image(bytes: 20_000_001)])
        #expect(vm.items.map(\.send) == [valid])
        #expect(vm.error == "画像を読み込めませんでした")
        #expect(vm.text == "本文 [Image #1] ")
    }

    @Test(arguments: Composer.allCases)
    func remainingSlotsKeepFirstValidImagesOnly(_ composer: Composer) async {
        let vm = Harness(composer)
        await vm.add([image(), image(), image()])
        let original = vm.items
        let fits = image(bytes: 2048)
        await vm.add([fits, image(bytes: 4096)])
        #expect(Array(vm.items.prefix(3)) == original)
        #expect(vm.items.last?.send == fits)
        #expect(vm.items.map(\.number) == [1, 2, 3, 4])
        #expect(vm.text == "本文 [Image #1] [Image #2] [Image #3] [Image #4] ")
        #expect(vm.error == "画像は最大4枚までです。1枚20MB・合計80MBまで添付できます。")
    }

    @Test(arguments: Composer.allCases)
    func allInvalidPreservesTextCursorAndExistingItems(_ composer: Composer) async {
        let vm = Harness(composer)
        await vm.add([image()])
        let items = vm.items
        let text = vm.text
        let cursor = vm.cursor
        await vm.add([broken, image(bytes: 20_000_001)])
        #expect(vm.items == items)
        #expect(vm.text == text)
        #expect(vm.cursor == cursor)
        #expect(vm.error == "画像を読み込めませんでした")
        await vm.add([])
        #expect(vm.error == "画像を読み込めませんでした")
    }

    @Test(arguments: Composer.allCases)
    func acceptsTwentyAndEightyMBExactly(_ composer: Composer) async {
        let vm = Harness(composer)
        let valid = image(bytes: 20_000_000)
        await vm.add(Array(repeating: valid, count: 4))
        #expect(vm.items.map(\.send) == Array(repeating: valid, count: 4))
        #expect(vm.error == nil)
        let items = vm.items
        let text = vm.text
        await vm.add([image()])
        #expect(vm.items == items)
        #expect(vm.text == text)
        #expect(vm.error == "画像は最大4枚までです。1枚20MB・合計80MBまで添付できます。")
    }

    @Test(arguments: Composer.allCases)
    func overEightyMBSelectionKeepsOnlyValidImages(_ composer: Composer) async {
        let vm = Harness(composer)
        let valid = image(bytes: 20_000_000)
        // 4枚で80MBを超すには1枚20MBも超すため、先に起きたA2を表示する。
        await vm.add([valid, image(bytes: 20_000_001), valid, valid])
        #expect(vm.items.map(\.send) == Array(repeating: valid, count: 3))
        #expect(vm.error == "画像は1枚あたり20MBまでです")
    }

    @Test(arguments: Composer.allCases)
    func checksBothEdgesAtIntake(_ composer: Composer) async throws {
        let vm = Harness(composer)
        let valid = try dimensionImage(width: 8000, height: 1)
        let tall = try dimensionImage(width: 1, height: 8000)
        await vm.add([
            try dimensionImage(width: 8001, height: 1), valid,
            try dimensionImage(width: 1, height: 8001), broken, tall,
        ])
        #expect(vm.items.map(\.send) == [valid, tall])
        #expect(vm.text == "本文 [Image #1] [Image #2] ")
        #expect(vm.error == "画像は各辺8000ピクセルまでです。必要な部分を切り出してください")
    }

    private func dimensionImage(width: Int, height: Int) throws -> SendAttachment {
        let pixels = Data(repeating: 255, count: width * height * 4)
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        let image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return SendAttachment(mediaType: "image/png", data: data as Data)
    }

    @Test(arguments: [false, true])
    func restoredTotalOverflowSkipsOnlyImageThatDoesNotFit(withLoadFailure: Bool) async {
        let original = SessionDetailViewModel.SessionAttachmentItem(
            number: 1, send: image(bytes: 70_000_000), previewData: Data([1])
        )
        let vm = SessionDetailViewModel(session: Session(
            id: "s1", name: "Rose", agent: .claudeCode, status: .idle,
            subtitle: "proj", updatedAt: Date(timeIntervalSince1970: 0)
        ), api: MockAPI(), recovery: .init(text: "本文 [Image #1] ", attachments: [original], errorMessage: "再送"))
        let small = image()
        if withLoadFailure {
            await vm.addAttachmentLoadResults([
                .success(image(bytes: 20_000_000)),
                .failure(URLError(.cannotDecodeContentData)),
                .success(small),
            ])
        } else {
            await vm.addAttachmentsFromPicker([image(bytes: 20_000_000), small])
        }
        #expect(vm.attachmentItems.first == original)
        #expect(vm.attachments == [original.send, small])
        #expect(vm.inputText == "本文 [Image #1] [Image #2] ")
        #expect(vm.attachmentError == "画像は合計80MBまでです")
    }

    @Test
    func restoredDimensionErrorKeepsDraftAndUsesA4OnSend() async throws {
        let attachment = SessionDetailViewModel.SessionAttachmentItem(
            number: 1, send: try dimensionImage(width: 8001, height: 1), previewData: Data()
        )
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: Session(
            id: "s1", name: "Rose", agent: .claudeCode, status: .idle,
            subtitle: "proj", updatedAt: Date(timeIntervalSince1970: 0)
        ), api: api, recovery: .init(text: "本文 [Image #1] ", attachments: [attachment], errorMessage: "再送"))
        await vm.sendMessage()
        #expect(vm.attachmentItems == [attachment])
        #expect(vm.inputText == "本文 [Image #1] ")
        #expect(vm.attachmentError == "画像は各辺8000ピクセルまでです。必要な部分を切り出してください")
        #expect(vm.sendState == .failed("画像は各辺8000ピクセルまでです。必要な部分を切り出してください"))
        #expect(await api.lastSentRequest == nil)
    }
}
