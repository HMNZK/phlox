import Vision

/// 静止画像から QR ペイロード文字列を抽出する（写真読み取り経路。Vision はホスト macOS でも動く）。
public enum QRImageDecoder {
    /// 画像中の最初の QR コードのペイロード文字列。QR が無ければ nil。
    public static func decodeQRString(from cgImage: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let observations = request.results else { return nil }
            return observations.first(where: { $0.symbology == .qr })?.payloadStringValue
        } catch {
            return nil
        }
    }
}
