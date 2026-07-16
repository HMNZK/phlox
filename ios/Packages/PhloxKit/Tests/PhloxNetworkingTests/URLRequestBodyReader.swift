import Foundation

extension URLRequest {
    /// URLSession 経由では `httpBody` が `httpBodyStream` に変換されるため、テストスタブ用にどちらからも読む。
    func readBodyForTesting() -> Data? {
        if let body = httpBody {
            return body
        }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufSize = 4096
        var buf = [UInt8](repeating: 0, count: bufSize)
        while stream.hasBytesAvailable {
            let n = stream.read(&buf, maxLength: bufSize)
            if n > 0 { data.append(contentsOf: buf[..<n]) }
        }
        return data
    }
}
