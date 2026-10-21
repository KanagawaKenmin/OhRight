// 所属层级：L1 积木层
// 文件职责：读写本应用的无压缩 ZIP，逐项验证目录、大小及 CRC。
// 输入：相对路径数据；输出：有界内存容器；不解压至任意路径。
// 依赖：Foundation、文件摘要；拒绝加密、压缩、链接、重复与穿越路径。
import Foundation

enum StoredZIP {
    static let maximumBytes = 250_000_000
    static let maximumFiles = 10_000
    static func safePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.contains("\\") && !path.contains(":") && !path.contains("\0") &&
            parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func encode(_ files: [String: Data]) throws -> Data {
        guard files.count <= maximumFiles, files.values.reduce(0, { $0 + $1.count }) <= maximumBytes else { throw invalid() }
        var data = Data(), directory = Data()
        for name in files.keys.sorted() {
            guard safePath(name), let content = files[name], name.utf8.count < 65536 else { throw invalid() }
            let filename = Data(name.utf8), offset = data.count, crc = FileDigest.crc32(content)
            data.put(0x04034b50, 4); data.put(20, 2); data.put(0x800, 2); data.put(0, 2)
            data.put(0, 2); data.put(33, 2); data.put(Int(crc), 4)
            data.put(content.count, 4); data.put(content.count, 4); data.put(filename.count, 2); data.put(0, 2)
            data.append(filename); data.append(content)
            directory.put(0x02014b50, 4); directory.put(20, 2); directory.put(20, 2); directory.put(0x800, 2)
            directory.put(0, 2); directory.put(0, 2); directory.put(33, 2); directory.put(Int(crc), 4)
            directory.put(content.count, 4); directory.put(content.count, 4); directory.put(filename.count, 2)
            directory.put(0, 2); directory.put(0, 2); directory.put(0, 2); directory.put(0, 2); directory.put(0, 4)
            directory.put(offset, 4); directory.append(filename)
        }
        let offset = data.count
        data.append(directory)
        data.put(0x06054b50, 4); data.put(0, 2); data.put(0, 2)
        data.put(files.count, 2); data.put(files.count, 2); data.put(directory.count, 4); data.put(offset, 4); data.put(0, 2)
        guard data.count <= maximumBytes else { throw invalid() }
        return data
    }

    static func decode(_ data: Data) throws -> [String: Data] {
        guard data.count >= 22, data.count <= maximumBytes else { throw invalid() }
        // 本应用只写无注释单卷 ZIP；严格校验尾部，拒绝尾随内容及 ZIP64。
        let end = data.count - 22
        guard try data.number(end, 4) == 0x06054b50, try data.number(end + 4, 4) == 0,
              try data.number(end + 20, 2) == 0 else { throw invalid() }
        let count = try data.number(end + 10, 2)
        guard count <= maximumFiles, try data.number(end + 8, 2) == count else { throw invalid() }
        let directorySize = try data.number(end + 12, 4), directoryOffset = try data.number(end + 16, 4)
        guard directoryOffset + directorySize == end else { throw invalid() }
        var cursor = directoryOffset, nextLocal = 0, files: [String: Data] = [:]
        for _ in 0..<count {
            guard try data.number(cursor, 4) == 0x02014b50,
                  try data.number(cursor + 8, 2) == 0x800, try data.number(cursor + 10, 2) == 0,
                  try data.number(cursor + 34, 2) == 0, try data.number(cursor + 38, 4) == 0 else { throw invalid() }
            let crc = try data.number(cursor + 16, 4), size = try data.number(cursor + 24, 4)
            let length = try data.number(cursor + 28, 2)
            let extra = try data.number(cursor + 30, 2), comment = try data.number(cursor + 32, 2)
            let offset = try data.number(cursor + 42, 4)
            guard size == (try data.number(cursor + 20, 4)), offset == nextLocal,
                  cursor + 46 + length + extra + comment <= end else { throw invalid() }
            let nameData = data.subdata(in: (cursor + 46)..<(cursor + 46 + length))
            guard let name = String(data: nameData, encoding: .utf8), safePath(name), files[name] == nil,
                  try data.number(offset, 4) == 0x04034b50, try data.number(offset + 6, 2) == 0x800,
                  try data.number(offset + 8, 2) == 0, try data.number(offset + 14, 4) == crc,
                  try data.number(offset + 18, 4) == size, try data.number(offset + 22, 4) == size,
                  try data.number(offset + 26, 2) == length else { throw invalid() }
            let localExtra = try data.number(offset + 28, 2)
            let start = offset + 30 + length + localExtra
            guard start + size <= directoryOffset,
                  data.subdata(in: (offset + 30)..<(offset + 30 + length)) == nameData else { throw invalid() }
            let content = data.subdata(in: start..<(start + size))
            guard Int(FileDigest.crc32(content)) == crc else { throw invalid() }
            files[name] = content
            nextLocal = start + size
            cursor += 46 + length + extra + comment
        }
        guard cursor == end, nextLocal == directoryOffset else { throw invalid() }
        return files
    }
    private static func invalid() -> DomainError { .invalid("备份 ZIP 损坏或格式不受支持，未替换资料。请选择本应用导出的完整 ZIP。") }
}

private extension Data {
    mutating func put(_ value: Int, _ count: Int) {
        for i in 0..<count { append(UInt8(truncatingIfNeeded: value >> (i * 8))) }
    }
    func number(_ offset: Int, _ count: Int) throws -> Int {
        guard offset >= 0, offset + count <= self.count else { throw DomainError.invalid("备份 ZIP 不完整。") }
        return (0..<count).reduce(0) { $0 | (Int(self[offset + $1]) << ($1 * 8)) }
    }
}
