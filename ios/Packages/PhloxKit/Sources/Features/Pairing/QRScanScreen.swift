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
    public static let title = "QR を読み取る"
    public static let reconnectTitle = "QR で再接続"
    public static let settingsEntryButtonTitle = "QR で再接続"
    public static let subtitle = "Mac に表示した QR を枠に入れてください。遠いときはピンチで拡大できます。"
    public static let cameraUnavailableGuidance = "カメラへのアクセスが許可されていません。"
    public static let pickPhotoButtonTitle = "写真から読み取る"
    public static let noQRInImage = "画像から QR を見つけられません"
    public static let noQRInImageGuidance = "QR 全体がはっきり写ったスクリーンショットを選んでください。"
    public static let applying = "接続先を保存しています…"
    public static let scanAgainButtonTitle = "もう一度スキャン"
    public static let reconnectGuidance = "読み取れるまで、今の接続先は変わりません。"
    public static let reconnectSuccessMessage = "これからは新しい接続先から一覧を読み込みます。"

    public static var cameraUnavailablePresentation: ErrorPresentation {
        ErrorPresentation(
            title: "カメラを使えません",
            message: cameraUnavailableGuidance,
            recoveryAction: pickPhotoButtonTitle,
            nextStep: "Mac の QR をスクリーンショットにして、写真から読み取れます。",
            isNeutral: true
        )
    }

    public static var imageQRNotFoundPresentation: ErrorPresentation {
        ErrorPresentation(
            title: noQRInImage,
            message: "選んだ画像の中に、読み取れる QR がありませんでした。",
            recoveryAction: pickPhotoButtonTitle,
            nextStep: noQRInImageGuidance
        )
    }

    public static func message(for error: PairingPayloadError) -> String {
        presentation(for: error).title
    }

    public static func presentation(for error: PairingPayloadError) -> ErrorPresentation {
        switch error {
        case .notPairingURL:
            return ErrorPresentation(
                title: "ペアリング用の QR ではありません",
                message: "読み取った QR は Phlox の接続用ではありません。",
                recoveryAction: "もう一度スキャン",
                nextStep: "Mac の Phlox が表示したペアリング用の QR を読み取ってください。",
                technicalDetail: "https://example.com/menu"
            )
        case .unsupportedVersion(let version):
            return ErrorPresentation(
                title: "この QR の版には対応していません",
                message: "QR の版（v）が無いか、このアプリが読めない版です。",
                recoveryAction: "もう一度スキャン",
                nextStep: "iPhone と Mac の Phlox を両方とも最新にしてから、QR を表示し直してください。",
                technicalDetail: "phlox://pair?v=\(version ?? "未指定")&host=…"
            )
        case .missingHost:
            return ErrorPresentation(
                title: "QR に接続先がありません",
                message: "QR の中に Mac のアドレス（host）が入っていません。",
                recoveryAction: "もう一度スキャン",
                nextStep: "Mac で QR を表示し直して、もう一度読み取ってください。",
                technicalDetail: "phlox://pair?v=1&port=8765&token=…"
            )
        case .invalidPort:
            return ErrorPresentation(
                title: "ポート番号が正しくありません",
                message: "QR の中のポート番号が、使える範囲（1〜65535）にありません。",
                recoveryAction: "もう一度スキャン",
                nextStep: "Mac の Phlox の設定でポートを確かめ、QR を表示し直してください。",
                technicalDetail: "port=99999"
            )
        case .invalidToken:
            return ErrorPresentation(
                title: "QR のトークンが正しくありません",
                message: "QR の中の接続の鍵（トークン）の形が違います。",
                recoveryAction: "もう一度スキャン",
                nextStep: "Mac で QR を表示し直して、もう一度読み取ってください。",
                technicalDetail: "token=…（64 桁の小文字 16 進ではない）"
            )
        }
    }

    public static func successTitle(name: String?) -> String {
        guard let name, !name.isEmpty else { return "接続しました" }
        return "接続しました（\(name)）"
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
    @Environment(\.dismiss) private var dismiss
    @Bindable private var applyViewModel: PairingApplyViewModel
    private let initialScannedString: String?
    private let isReconnection: Bool
    private let previousEndpoint: String?
    private let onApplied: ((String?) -> Void)?

    @State private var parseErrorMessage: String?
    @State private var parseErrorPresentation: ErrorPresentation?
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
        isReconnection: Bool = false,
        previousEndpoint: String? = nil,
        onApplied: ((String?) -> Void)? = nil
    ) {
        self.applyViewModel = applyViewModel
        self.initialScannedString = initialScannedString
        self.isReconnection = isReconnection
        self.previousEndpoint = previousEndpoint
        self.onApplied = onApplied
    }

    public var body: some View {
        scanBody
            .background(Color.black.ignoresSafeArea())
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
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
                onApplied?(applyViewModel.appliedName)
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
        ZStack(alignment: .bottom) {
            IOSColor.bg.scanner.ignoresSafeArea()
            VStack(spacing: 0) {
                if shouldShowScanner && cameraScannerUnavailable {
                    Spacer(minLength: 0)
                    cameraUnavailableFallback.offset(y: -43)
                    Spacer(minLength: 0)
                } else if shouldShowScanner {
                    Text(scannerGuidance)
                        .font(DSFont.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DSSpacing.l)
                        .padding(.top, DSSpacing.l)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                navigationHeader
                    .padding(.horizontal, DSSpacing.m)
            }

            statusSection
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
    }

    private var navigationHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(DSFont.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isReconnection ? "設定へ戻る" : "接続設定へ戻る")

            Spacer(minLength: 0)
            Text(isReconnection ? QRScanCopy.reconnectTitle : QRScanCopy.title)
                .font(DSFont.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)

            Color.clear.frame(width: 44, height: 44)
        }
    }

    /// カメラ不可（シミュレータ・権限拒否）のときだけ案内を出す。
    /// カメラ利用可能な実スキャン中は `fullScreenScanner` が画面全体に描画する。
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

    private var cameraScannerUnavailable: Bool {
        #if os(iOS)
        !isCameraScannerAvailable
        #else
        true
        #endif
    }

    private var cameraUnavailableFallback: some View {
        VStack(spacing: DSSpacing.l) {
            ZStack {
                Image(systemName: "camera")
                    .font(DSFont.title2.weight(.regular))
                    .foregroundStyle(.white)
                Path { path in
                    path.move(to: CGPoint(x: 18, y: 18))
                    path.addLine(to: CGPoint(x: 46, y: 46))
                }
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .frame(width: 64, height: 64)
            .background(Color.white.opacity(0.12), in: Circle())
            Text(QRScanCopy.cameraUnavailablePresentation.title)
                .font(DSFont.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text(QRScanCopy.cameraUnavailablePresentation.message)
                .font(DSFont.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            photoPickerButton
            Text("設定アプリでカメラを許可")
                .font(DSFont.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, DSSpacing.xl)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var photoPickerButton: some View {
        #if os(iOS)
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "photo")
                Text(QRScanCopy.pickPhotoButtonTitle)
                    .font(DSFont.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color.black)
            .background(Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        #endif
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            if let parseErrorMessage {
                VStack(alignment: .leading, spacing: DSSpacing.m) {
                    if let parseErrorPresentation {
                        PairingErrorCard(presentation: parseErrorPresentation)
                    } else {
                        Text(parseErrorMessage)
                            .font(DSFont.body)
                            .foregroundStyle(.white)
                    }
                    if parseErrorPresentation?.recoveryAction == QRScanCopy.pickPhotoButtonTitle {
                        photoPickerButton
                    } else {
                        scanAgainButton
                    }
                }
            }

            phaseStatusSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var phaseStatusSection: some View {
        switch applyViewModel.phase {
        case .idle:
            EmptyView()
        case .applying:
            HStack(alignment: .top, spacing: DSSpacing.m) {
                staticProgressIndicator
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(QRScanCopy.applying)
                        .font(DSFont.headline)
                        .foregroundStyle(DSColor.textPrimary)
                    Text("読み取った QR から接続先を取り出しました。")
                        .font(DSFont.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                    if let config = applyViewModel.applyingConnection {
                        Text("\(config.host):\(String(config.port))")
                            .font(DSFont.campMonoCaption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        case .success(let name) where !isRescanning:
            PairingSuccessCard(
                title: QRScanCopy.successTitle(name: name),
                message: isReconnection ? QRScanCopy.reconnectSuccessMessage : "新しい接続先からセッション一覧を読み込みます。",
                endpoint: applyViewModel.applyingConnection.map { "\($0.host):\($0.port)" }
            )
        case .unreachable where !isRescanning:
            VStack(alignment: .leading, spacing: DSSpacing.m) {
                PairingErrorCard(presentation: PairingCopy.unreachablePresentation)
                scanAgainButton
            }
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
                .foregroundStyle(IOSColor.accentOnFill)
                .background(IOSColor.accent, in: Capsule())
                .overlay(
                    RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                        .strokeBorder(DSColor.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var staticProgressIndicator: some View {
        ZStack {
            Circle()
                .stroke(IOSColor.text.tertiary.opacity(0.22), lineWidth: 2)
            Circle()
                .trim(from: 0, to: 0.24)
                .stroke(IOSColor.text.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private var scannerGuidance: String {
        guard isReconnection else { return QRScanCopy.subtitle }
        guard let previousEndpoint else { return QRScanCopy.reconnectGuidance }
        return "読み取れるまで、今の接続先 \(previousEndpoint) は変わりません。"
    }

    private func handleScannedString(_ string: String) {
        guard applyViewModel.phase != .applying else { return }
        parseErrorMessage = nil
        isScannerPaused = true
        isRescanning = false

        switch QRScanLogic.parse(string) {
        case .success(let payload):
            parseErrorPresentation = nil
            Task { await applyViewModel.apply(payload) }
        case .failure(let message):
            parseErrorMessage = message
            if case .failure(let error) = PairingPayloadParser.parse(string) {
                parseErrorPresentation = QRScanCopy.presentation(for: error)
            }
        }
    }

    private func resetForRescan() {
        parseErrorMessage = nil
        parseErrorPresentation = nil
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
                VStack(spacing: DSSpacing.xs) {
                    navigationHeader
                        .padding(.horizontal, DSSpacing.m)
                    Text(scannerGuidance)
                        .font(DSFont.subheadline)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DSSpacing.m)
                        .padding(.bottom, DSSpacing.m)
                }
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.45))
            }
    }

    @MainActor
    private func decodePhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        guard applyViewModel.phase != .applying else { return }
        parseErrorMessage = nil

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let cgImage = image.cgImage else {
                showQRNotFoundInPhoto()
                return
            }
            if let string = QRImageDecoder.decodeQRString(from: cgImage) {
                handleScannedString(string)
            } else {
                showQRNotFoundInPhoto()
            }
        } catch {
            showQRNotFoundInPhoto()
        }
    }

    private func showQRNotFoundInPhoto() {
        parseErrorMessage = QRScanCopy.noQRInImage
        parseErrorPresentation = QRScanCopy.imageQRNotFoundPresentation
    }
    #endif
}

private struct PairingErrorCard: View {
    let presentation: ErrorPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text(presentation.title)
                .font(DSFont.headline.weight(.semibold))
                .foregroundStyle(presentation.isNeutral ? IOSColor.text.primary : IOSColor.status.error)
            Text(presentation.cause)
                .font(DSFont.body)
                .foregroundStyle(IOSColor.text.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !presentation.nextStep.isEmpty {
                Text(presentation.nextStep)
                    .font(DSFont.body)
                    .foregroundStyle(IOSColor.text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = presentation.technicalDetail {
                Text(detail)
                    .font(DSFont.campMonoCaption)
                    .foregroundStyle(IOSColor.text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.m)
        .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

private struct PairingSuccessCard: View {
    let title: String
    let message: String
    let endpoint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .font(DSFont.headline)
                .foregroundStyle(IOSColor.status.success)
            Text(message)
                .font(DSFont.body)
                .foregroundStyle(IOSColor.text.secondary)
            if let endpoint {
                Text(endpoint)
                    .font(DSFont.campMonoCaption)
                    .foregroundStyle(IOSColor.text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.m)
        .background(IOSColor.bg.card, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
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
