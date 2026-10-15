// 所属层级：L1 积木层
// 文件职责：提供可复现的非加密随机源用于洗牌与排程测试。
// 输入：种子；输出：随机数；依赖：Swift 标准库。
// 禁止事项：不得用于密钥、身份令牌或安全用途。
struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
