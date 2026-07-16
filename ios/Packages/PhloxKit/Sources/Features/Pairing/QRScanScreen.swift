import SwiftUI
import DesignSystemIOS
import PhloxCore

#if os(iOS)
import PhotosUI
import VisionKit
import UIKit
#endif

/// 文言（テスト可能なコピー層）。
public enum QRScanCopy {
    public static let title = "QR でスキャン"
    public static let settingsEntryButtonTitle = "QR でスキャン"
    public static let subtitle = "Mac に表示されたペアリング用 QR を読み取ります"
    public static let cameraUnavailableGuidance =
        "カメラを利用できません。シミュレーターの場合は「写真から読み取る」で QR 画像を選択してください。"
    public static let pickPhotoButtonTitle = "写真から読み取る"
    public static let noQRInImage = "画像から QR コードを読み取れませんでした"
    public static let applying = "接続情報を適用しています…"
    public static let scanAgainButtonTitle = "もう一度スキャンする"

    public static func message(for error: PairingPayloadError) -> String {
        switch error {
        case .notPairingURL:
            return "ペアリング用の QR コードではありません"
        case .unsupportedVersion:
            return "未対応の QR バージョンです"
        case .missingHost:
            return "ホスト情報が見つかりません"
        case .invalidPort:
            return "ポート番号が不正です"
        case .invalidToken:
            return "トークンが不正です"
        }
    }

    public static func successMessage(name: String?) -> String {
        if let name, !name.isEmpty {
            return "接続しました（\(name)）"
        }
        return "接続しました"
    }
}

/// カスタム URL スキーム経由では scheme/host の大文字小文字が正規化されない場合があるため lowercase 化する。
public enum PairingURLNormalizer {
    public static func normalizedString(from url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        if let scheme = components.scheme {
            components.scheme = scheme.lowercased()
        }
        if let host = components.host {
            components.host = host.lowercased()
        }
        return components.string ?? url.absoluteString
    }
}

/// 読み取り文字列のパース結果を画面向けメッセージへ変換する（白箱テスト対象）。
public enum QRScanLogic {
    public enum ParseOutcome: Equatable {
        case success(PairingPayload)
        case failure(String)
    }

    public static func parse(_ string: String) -> ParseOutcome {
        switch PairingPayloadParser.parse(string) {
        case .success(let payload):
            return .success(payload)
        case .failure(let error):
            return .failure(QRScanCopy.message(for: error))
        }
    }
}

/// `onApplied` コールバックの発火判定（白箱テスト対象）。
public enum QRScanAppliedCallbackLogic {
    /// `phase` が `.success` に遷移したとき、まだ発火していなければ `true`。
    public static func shouldFireOnApplied(
        previousPhase: PairingApplyViewModel.Phase,
        currentPhase: PairingApplyViewModel.Phase,
        hasAlreadyFired: Bool
    ) -> Bool {
        guard !hasAlreadyFired else { return false }
        guard case .success = currentPhase else { return false }
        if case .success = previousPhase { return false }
        return true
    }
}

/// スキャン画面。実機: VisionKit DataScannerViewController でカメラ読み取り。
/// カメラ不可（シミュレータ・権限拒否）: 案内文言＋「写真から読み取る」(PhotosPicker) のみ表示。
/// 読み取り文字列 → PairingPayloadParser.parse → 成功なら PairingApplyViewModel.apply → 結果表示。
public struct QRScanScreen: View {
    @Bindable private var applyViewModel: PairingApplyViewModel
    private let initialScannedString: String?
    private let onApplied: (() -> Void)?

    @State private var parseErrorMessage: String?
    @State private var hasConsumedInitialPayload = false
    @State private var isScannerPaused = false
    @State private var isRescanning = false
    @State private var hasFiredOnApplied = false

    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

    public init(
        applyViewModel: PairingApplyViewModel,
        initialScannedString: String? = nil,
        onApplied: (() -> Void)? = nil
    ) {
        self.applyViewModel = applyViewModel
        self.initialScannedString = initialScannedString
        self.onApplied = onApplied
    }

    public var body: some View {
        scanBody
            .background(DSColor.background)
            .navigationTitle(QRScanCopy.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task(id: initialScannedString) {
                await processInitialPayloadIfNeeded()
            }
            #if os(iOS)
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await decodePhoto(item) }
            }
            #endif
            .onChange(of: applyViewModel.phase) { oldPhase, newPhase in
                guard QRScanAppliedCallbackLogic.shouldFireOnApplied(
                    previousPhase: oldPhase,
                    currentPhase: newPhase,
                    hasAlreadyFired: hasFiredOnApplied
                ) else { return }
                hasFiredOnApplied = true
                onApplied?()
            }
    }

    /// スキャン実行中はカメラを画面全体に表示し、それ以外（カメラ不可・処理中・結果）は
    /// 従来どおり案内・状態をスクロール表示する。
    @ViewBuilder
    private var scanBody: some View {
        #if os(iOS)
        if isLiveScanning {
            fullScreenScanner
        } else {
            scrollableContent
        }
        #else
        scrollableContent
        #endif
    }

    private var scrollableContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                header
                scanContent
                statusSection
            }
            .padding(DSSpacing.l)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(QRScanCopy.subtitle)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    /// カメラ不可（シミュレータ・権限拒否）のときだけ案内を出す。
    /// カメラ利用可能な実スキャン中は `fullScreenScanner` が画面全体に描画する。
    @ViewBuilder
    private var scanContent: some View {
        if shouldShowScanner {
            #if os(iOS)
            if !isCameraScannerAvailable {
                cameraUnavailableFallback
            }
            #else
            cameraUnavailableFallback
            #endif
        }
    }

    private var shouldShowScanner: Bool {
        switch applyViewModel.phase {
        case .idle:
            return true
        case .applying:
            return false
        case .success, .unreachable:
            return isRescanning
        }
    }

    private var cameraUnavailableFallback: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text(QRScanCopy.cameraUnavailableGuidance)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textSecondary)
            photoPickerButton
        }
    }

    @ViewBuilder
    private var photoPickerButton: some View {
        #if os(iOS)
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "photo.on.rectangle")
                Text(QRScanCopy.pickPhotoButtonTitle)
                    .font(DSFont.headline)
            }
            .frame(maxWidth: .infinity, minHeight: DSTouch.minSize)
            .foregroundStyle(DSColor.accent)
            .background(DSColor.surfaceElevated, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                    .strokeBorder(DSColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    private var statusSection: some View {
        if let parseErrorMessage {
            DSResultBanner(message: parseErrorMessage, isError: true)
            scanAgainButton
        }

        switch applyViewModel.phase {
        case .idle:
            EmptyView()
        case .applying:
            VStack(spacing: DSSpacing.m) {
                DSConnectingIndicator(size: 96)
                Text(QRScanCopy.applying)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DSSpacing.xl)
        case .success(let name) where !isRescanning:
            DSResultBanner(message: QRScanCopy.successMessage(name: name), isError: false)
        case .unreachable(let guidance) where !isRescanning:
            DSResultBanner(message: guidance, isError: true)
            scanAgainButton
        case .success, .unreachable:
            EmptyView()
        }
    }

    private var scanAgainButton: some View {
        Button {
            resetForRescan()
        } label: {
            Text(QRScanCopy.scanAgainButtonTitle)
                .font(DSFont.headline)
                .frame(maxWidth: .infinity, minHeight: DSTouch.minSize)
                .foregroundStyle(DSColor.accent)
                .background(DSColor.surfaceElevated, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .strokeBorder(DSColor.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func handleScannedString(_ string: String) {
        guard applyViewModel.phase != .applying else { return }
        parseErrorMessage = nil
        isScannerPaused = true
        isRescanning = false

        switch QRScanLogic.parse(string) {
        case .success(let payload):
            Task { await applyViewModel.apply(payload) }
        case .failure(let message):
            parseErrorMessage = message
        }
    }

    private func resetForRescan() {
        parseErrorMessage = nil
        isScannerPaused = false
        isRescanning = true
        #if os(iOS)
        selectedPhotoItem = nil
        #endif
    }

    @MainActor
    private func processInitialPayloadIfNeeded() async {
        guard !hasConsumedInitialPayload, let initialScannedString else { return }
        hasConsumedInitialPayload = true
        handleScannedString(initialScannedString)
    }

    #if os(iOS)
    private var isCameraScannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    /// カメラを画面全体に出して読み取り中かどうか。
    private var isLiveScanning: Bool {
        shouldShowScanner && isCameraScannerAvailable && !isScannerPaused
    }

    /// カメラプレビューをナビゲーションバー下から画面下端まで全面に広げ、
    /// 読み取り案内を上部にスクリム付きでオーバーレイする。
    private var fullScreenScanner: some View {
        QRDataScannerRepresentable { handleScannedString($0) }
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                Text(QRScanCopy.subtitle)
                    .font(DSFont.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(DSSpacing.m)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.45))
            }
    }

    @MainActor
    private func decodePhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard applyViewModel.phase != .applying else { return }
        parseErrorMessage = nil

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let cgImage = image.cgImage
        else {
            parseErrorMessage = QRScanCopy.noQRInImage
            return
        }

        if let string = QRImageDecoder.decodeQRString(from: cgImage) {
            handleScannedString(string)
        } else {
            parseErrorMessage = QRScanCopy.noQRInImage
        }
    }
    #endif
}

#if os(iOS)
private struct QRDataScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !context.coordinator.didDetectCode else { return }
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        if uiViewController.isScanning {
            uiViewController.stopScanning()
        }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var didDetectCode = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !didDetectCode else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue
                else { continue }
                didDetectCode = true
                dataScanner.stopScanning()
                onCode(payload)
                return
            }
        }
    }
}
#endif
