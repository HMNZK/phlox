public enum SessionRuntimeUpdateCompatibility {
    public static func allows(minimum: String?, maximum: String?, runtimeProtocol: Int) -> Bool {
        guard let minimum, let maximum,
              let lower = Int(minimum), let upper = Int(maximum),
              lower > 0, lower <= upper else { return false }
        return (lower...upper).contains(runtimeProtocol)
    }
}
