import Foundation

/// permission の外側の nil は省略、内側の nil は明示的な既定への変更。
public struct ControlSettingsUpdate: Decodable, Equatable, Sendable {
    public var effort: String?
    public var permission: String??
    public let planMode: Bool?

    public init(effort: String? = nil, permission: String?? = nil, planMode: Bool? = nil) {
        self.effort = effort
        self.permission = permission
        self.planMode = planMode
    }

    public var isEmpty: Bool { effort == nil && permission == nil && planMode == nil }

    private enum CodingKeys: String, CodingKey { case effort, permission, planMode }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        effort = try values.contains(.effort) ? values.decode(String.self, forKey: .effort) : nil
        if values.contains(.permission) {
            permission = try values.decodeNil(forKey: .permission)
                ? .some(nil) : .some(values.decode(String.self, forKey: .permission))
        } else {
            permission = nil
        }
        planMode = try values.contains(.planMode) ? values.decode(Bool.self, forKey: .planMode) : nil
    }
}
