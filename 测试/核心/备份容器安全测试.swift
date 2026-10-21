// 测试边界：校验标准摘要向量、ZIP 截断、路径穿越和重复目录攻击。
// 输入：固定字节和故意损坏的 ZIP；输出：明确拒绝断言。
// 不写入用户目录；macOS 额外使用系统 unzip 验证互通。
import Foundation
import XCTest
#if canImport(OhRightCore)
@testable import OhRightCore
#else
@testable import OhRight
#endif

final class BackupContainerSafetyTests: XCTestCase {
    func testStandardHashVectors() {
        XCTAssertEqual(FileDigest.sha256(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(FileDigest.sha256(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(FileDigest.crc32(Data("123456789".utf8)), 0xcbf43926)
    }

    func testZIPRejectsTraversalCorruptionAndTruncation() throws {
        for name in ["../manifest.json", "/root", "a/../../b", "a\\b", "C:/data", "a//b", "a/./b"] {
            XCTAssertFalse(StoredZIP.safePath(name))
            XCTAssertThrowsError(try StoredZIP.encode([name: Data()]))
        }
        let zip = try StoredZIP.encode(["manifest.json": Data("payload".utf8)])
        for length in [0, 10, zip.count - 1] { XCTAssertThrowsError(try StoredZIP.decode(Data(zip.prefix(length)))) }
        var corrupt = zip; corrupt[30 + "manifest.json".utf8.count] ^= 0xff
        XCTAssertThrowsError(try StoredZIP.decode(corrupt))
        XCTAssertEqual(try StoredZIP.decode(zip)["manifest.json"], Data("payload".utf8))
    }

    func testDuplicateNamesAndCompressedEntriesAreRejected() throws {
        var zip = try StoredZIP.encode(["a": Data("1".utf8), "b": Data("2".utf8)])
        // 两个本地头均为 30 + 1 文件名 + 1 内容；中央目录每项为 46 + 1。
        let directory = 64
        zip[32 + 30] = 97
        zip[directory + 47 + 46] = 97
        XCTAssertThrowsError(try StoredZIP.decode(zip))
        var compressed = try StoredZIP.encode(["a": Data("1".utf8)])
        compressed[8] = 8
        XCTAssertThrowsError(try StoredZIP.decode(compressed))
    }

}

#if canImport(AppKit)
final class ZIPInteroperabilityTests: XCTestCase {
    func testZIPCanBeReadBySystemUnzip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: url) }
        try StoredZIP.encode(["manifest.json": Data("{}".utf8), "便条.md": Data("内容".utf8)]).write(to: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", url.path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
#endif
