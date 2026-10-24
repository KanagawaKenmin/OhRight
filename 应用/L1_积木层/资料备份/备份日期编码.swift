// 所属层级：L1 积木层
// 文件职责：按备份日期标记选择编码语义，兼容旧毫秒时间戳。
// 输入：备份头；输出：日期解码策略；未知格式明确拒绝。
// 依赖：Foundation、L0；不改变数据库、时区或日期值。
import Foundation

enum BackupDateCoding {
    static let lossless = "referenceSeconds"
    static let legacy = "unixMilliseconds"

    private struct Header: Decodable {
        var formatVersion: Int
        var dateEncoding: String?
    }

    /// Date 原生参考秒数避免纪元平移和乘除 1000 引入的浮点往返误差。
    static func decoder(for data: Data) throws -> JSONDecoder {
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard (1...2).contains(header.formatVersion) else { throw DomainError.invalid("暂不支持这个备份版本。") }
        let decoder = JSONDecoder()
        if header.dateEncoding == nil || header.dateEncoding == legacy {
            decoder.dateDecodingStrategy = .millisecondsSince1970
        } else if header.formatVersion == 2 && header.dateEncoding == lossless {
            decoder.dateDecodingStrategy = .deferredToDate
        } else {
            throw DomainError.invalid("备份日期格式无法识别，未替换任何资料。")
        }
        return decoder
    }
}
