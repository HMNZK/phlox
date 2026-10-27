import Vision

/// 静止画像から QR ペイロード文字列を抽出する（写真読み取り経路。Vision はホスト macOS でも動く）。
public enum QRImageDecoder {
    /// 画像中の最初の QR コードのペイロード文字列。QR が無ければ nil。
    public static func decodeQRString(from cgImage: CGImage) -> String? {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            let error = error as NSError
            guard error.domain == VNErrorDomain, error.code == VNErrorCode.internalError.rawValue,
                  request.revision != VNDetectBarcodesRequestRevision1 else { return nil }
            request.revision = VNDetectBarcodesRequestRevision1
            do {
                try handler.perform([request])
            } catch {
                return nil
            }
        }
        return request.results?.first(where: { $0.symbology == .qr })?.payloadStringValue
    }
}
