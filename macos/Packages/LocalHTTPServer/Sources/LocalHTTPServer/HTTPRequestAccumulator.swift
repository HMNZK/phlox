import Foundation

/// 受信チャンクを蓄積し、ヘッダ終端オフセットと Content-Length を一度だけ検出して
/// キャッシュするインクリメンタルなリクエスト組み立て器。
/// 旧実装(チャンク毎の exceedsMaxBodyLength/isComplete + 完了後 parse の再走査)と
/// 同じ判定順序・同じ閾値挙動を保ったまま、走査を増分のみに抑える。
struct HTTPRequestAccumulator: Sendable {
    enum Progress: Sendable {
        case needsMore
        case complete
    }

    private static let headerTerminator = Data("\r\n\r\n".utf8)

    private var buffer = Data()
    /// ヘッダ終端(\r\n\r\n)直後のオフセット。一度検出したら再走査しない。
    private var bodyStart: Int?
    private var headerDecodable = false
    /// ヘッダから一度だけ抽出した Content-Length(無指定は 0。旧 isComplete と同じ)。
    private var contentLength = 0
    private var completed = false

    let maxBodyLength: Int

    init(maxBodyLength: Int = HTTPMessageParser.maxBodyLength) {
        self.maxBodyLength = maxBodyLength
    }

    var isEmpty: Bool {
        buffer.isEmpty
    }

    /// チャンクを追加し、旧実装と同じ順序(超過判定 → 完了判定)で進捗を返す。
    mutating func append(_ chunk: Data) throws -> Progress {
        // 終端 4 バイトがチャンク境界をまたぐ場合に備え、直前 3 バイトから探し直す
        let searchStart = max(buffer.count - 3, 0)
        buffer.append(chunk)

        if bodyStart == nil,
           let range = buffer.range(of: Self.headerTerminator, in: searchStart..<buffer.count) {
            bodyStart = range.upperBound
            // ヘッダはここで一度だけ復号して Content-Length を抽出する
            if let headerText = String(data: buffer[..<range.lowerBound], encoding: .utf8) {
                headerDecodable = true
                contentLength = HTTPMessageParser.contentLength(in: headerText) ?? 0
            }
        }

        guard let bodyStart else {
            // ヘッダ終端が未到着の間は全長で超過を判定する(旧 exceedsMaxBodyLength と同じ)
            if buffer.count > maxBodyLength {
                throw HTTPMessageParserError.payloadTooLarge
            }
            return .needsMore
        }

        // I1: 超過判定を headerDecodable guard の前へ置く。非UTF-8ヘッダ
        // (headerDecodable==false)で bodyStart 以降が無制限成長する経路を塞ぐ。
        // 判定は body 長(buffer.count - bodyStart)で行い、正常な分割到着(body が
        // 上限内)は 413 で誤爆させない。旧実装の body 側超過判定と同一閾値。
        if buffer.count - bodyStart > maxBodyLength {
            throw HTTPMessageParserError.payloadTooLarge
        }

        // ヘッダが UTF-8 として復号できない場合、旧実装は超過とも完了とも判定しない
        guard headerDecodable else {
            return .needsMore
        }

        // 宣言 Content-Length による超過はヘッダ復号後にのみ判定できる
        if contentLength > maxBodyLength {
            throw HTTPMessageParserError.payloadTooLarge
        }

        if buffer.count >= bodyStart + contentLength {
            completed = true
            return .complete
        }
        return .needsMore
    }

    /// 完了済みバッファからリクエストを構築する。未完了(EOF 等)なら incomplete。
    /// ボディは旧 parse と同じく Content-Length を超えた残余バイトも含めて返す。
    func makeRequest() throws -> HTTPRequest {
        guard completed, let bodyStart else {
            throw HTTPMessageParserError.incomplete
        }

        let headerData = Data(buffer[..<(bodyStart - Self.headerTerminator.count)])
        let body = Data(buffer[bodyStart...])
        return try HTTPMessageParser.makeRequest(headerData: headerData, body: body)
    }
}
