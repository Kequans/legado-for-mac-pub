import Foundation
import CryptoKit
import CoreFoundation

/// 文件管理工具（避免与 Foundation.FileManager 冲突）
enum FileUtils {
    private static var fm: Foundation.FileManager { Foundation.FileManager() }
    private static let localBookSourceFileName = "source.txt"
    
    /// 获取应用支持目录
    static func getAppSupportDirectory() -> URL? {
        return try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Legado", isDirectory: true)
    }
    
    /// 获取书籍缓存目录
    static func getBooksDirectory() -> URL? {
        guard let appSupport = getAppSupportDirectory() else { return nil }
        let booksDir = appSupport.appendingPathComponent("Books", isDirectory: true)
        try? fm.createDirectory(at: booksDir, withIntermediateDirectories: true)
        return booksDir
    }
    
    /// 获取章节缓存路径
    static func getChapterCachePath(bookUrl: String, chapterIndex: Int) -> URL? {
        guard let booksDir = getBooksDirectory() else { return nil }
        let bookId = bookUrl.md5
        let chapterFile = booksDir
            .appendingPathComponent(bookId, isDirectory: true)
            .appendingPathComponent("\(chapterIndex).txt")
        return chapterFile
    }

    /// 获取本地书籍的合并源文件路径。
    ///
    /// 本地 TXT/EPUB 导入只保存一个规范化的 UTF-8 源文件，章节通过
    /// BookChapter.start/end 定位。这样导入时不需要为每一章单独写文件。
    static func getLocalBookSourcePath(bookUrl: String) -> URL? {
        guard let booksDir = getBooksDirectory() else { return nil }
        return booksDir
            .appendingPathComponent(bookUrl.md5, isDirectory: true)
            .appendingPathComponent(localBookSourceFileName)
    }
    
    /// 缓存章节内容
    static func cacheChapterContent(bookUrl: String, chapterIndex: Int, content: String) {
        guard let filePath = getChapterCachePath(bookUrl: bookUrl, chapterIndex: chapterIndex) else {
            return
        }
        
        do {
            try fm.createDirectory(
                at: filePath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: filePath, atomically: true, encoding: .utf8)
        } catch {
            print("缓存章节失败: \(error)")
        }
    }

    /// 缓存本地书籍的规范化源文件。
    @discardableResult
    static func cacheLocalBookSource(bookUrl: String, content: String) -> Bool {
        guard let filePath = getLocalBookSourcePath(bookUrl: bookUrl) else {
            return false
        }

        do {
            try fm.createDirectory(
                at: filePath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(content.utf8).write(to: filePath, options: .atomic)
            return true
        } catch {
            print("缓存本地书籍源文件失败: \(error)")
            return false
        }
    }
    
    /// 读取缓存的章节内容
    static func getCachedChapterContent(bookUrl: String, chapterIndex: Int) -> String? {
        guard let filePath = getChapterCachePath(bookUrl: bookUrl, chapterIndex: chapterIndex) else {
            return nil
        }
        
        return try? String(contentsOf: filePath, encoding: .utf8)
    }

    /// 按章节范围读取本地书籍内容。
    ///
    /// 新导入的本地书籍使用 UTF-8 字节范围读取，不会把整本书再次加载到内存。
    /// 旧版本已经生成的章节缓存仍然优先使用；没有缓存时再兼容旧的原始文件路径。
    static func readLocalChapterContent(bookUrl: String, chapter: BookChapter) -> String? {
        if let cached = getCachedChapterContent(bookUrl: bookUrl, chapterIndex: chapter.index) {
            return cached
        }

        if let start = chapter.start,
           let end = chapter.end,
           start >= 0,
           end > start,
           let sourcePath = getLocalBookSourcePath(bookUrl: bookUrl),
           let content = readUTF8Range(from: sourcePath, start: start, end: end) {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 兼容没有源文件的旧数据或用户移动过原始文件的情况。
        return readChapterFromOriginalFile(bookUrl: bookUrl, chapter: chapter)
    }
    
    /// 清除书籍缓存
    static func clearBookCache(bookUrl: String) {
        guard let booksDir = getBooksDirectory() else { return }
        let bookId = bookUrl.md5
        let bookDir = booksDir.appendingPathComponent(bookId, isDirectory: true)
        try? fm.removeItem(at: bookDir)
    }
    
    /// 清除所有缓存
    static func clearAllCache() {
        guard let booksDir = getBooksDirectory() else { return }
        try? fm.removeItem(at: booksDir)
    }

    private static func readUTF8Range(from url: URL, start: Int64, end: Int64) -> String? {
        let length = end - start
        guard start >= 0,
              length > 0,
              length <= Int64(Int.max),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }

        defer { handle.closeFile() }
        handle.seek(toFileOffset: UInt64(start))
        let data = handle.readData(ofLength: Int(length))
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func readChapterFromOriginalFile(bookUrl: String, chapter: BookChapter) -> String? {
        let fileURL = URL(fileURLWithPath: bookUrl)
        guard let data = try? Data(contentsOf: fileURL),
              let source = decodeLocalText(data) else {
            return nil
        }

        if let start = chapter.start,
           let end = chapter.end,
           let range = stringRange(in: source, start: start, end: end) {
            return String(source[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stringRange(in source: String, start: Int64, end: Int64) -> Range<String.Index>? {
        guard start >= 0, end > start,
              start <= Int64(Int.max), end <= Int64(Int.max) else {
            return nil
        }

        // 新导入数据保存的是 UTF-8 字节范围。
        if let utf8Start = source.utf8.index(
            source.utf8.startIndex,
            offsetBy: Int(start),
            limitedBy: source.utf8.endIndex
        ),
           let utf8End = source.utf8.index(
               source.utf8.startIndex,
               offsetBy: Int(end),
               limitedBy: source.utf8.endIndex
           ),
           let stringStart = String.Index(utf8Start, within: source),
           let stringEnd = String.Index(utf8End, within: source),
           stringStart <= stringEnd {
            return stringStart..<stringEnd
        }

        // 旧数据可能保存的是 NSString 的 UTF-16 偏移。
        let nsSource = source as NSString
        let nsStart = Int(start)
        let nsEnd = min(Int(end), nsSource.length)
        guard nsStart >= 0, nsStart < nsEnd else { return nil }
        return Range(NSRange(location: nsStart, length: nsEnd - nsStart), in: source)
    }

    private static func decodeLocalText(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [
            .utf8,
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue)
            )),
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            )),
            .utf16,
            .ascii,
            .isoLatin1
        ]

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return text
            }
        }
        return nil
    }
}

/// String 扩展
extension String {
    /// 计算MD5
    var md5: String {
        let digest = Insecure.MD5.hash(data: Data(utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// URL编码
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

/// 日期格式化工具
extension Date {
    /// 格式化为字符串
    func formatted(_ format: String = "yyyy-MM-dd HH:mm:ss") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }
    
    /// 相对时间描述
    var relativeDescription: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)
        
        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            return "\(Int(interval / 60))分钟前"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))小时前"
        } else if interval < 604800 {
            return "\(Int(interval / 86400))天前"
        } else {
            return formatted("yyyy-MM-dd")
        }
    }
}
