import Foundation

/// Legado macOS 的可移植备份格式。
///
/// 使用 JSON 而不是直接复制 SQLite 文件，避免把 WAL 临时状态带到另一台 Mac，
/// 也让用户可以在需要时检查或迁移备份内容。
struct LegadoBackup: Codable {
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    var books: [Book]
    var bookSources: [BookSource]
    var chapters: [BookChapter]
    var chapterContents: [ChapterContent]
    var bookmarks: [Bookmark]
    var readRecords: [ReadRecord]
    var replaceRules: [ReplaceRule]
    var rssSources: [RSSSource]
    var articles: [Article]
    var localChapterFiles: [String: String]
}

enum BackupError: Error, LocalizedError {
    case invalidBackup
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBackup:
            return "备份文件格式无效"
        case .unsupportedVersion(let version):
            return "不支持的备份版本: \(version)"
        }
    }
}

final class BackupService {
    static let shared = BackupService()

    private let bookDAO = BookDAO()
    private let bookSourceDAO = BookSourceDAO()
    private let chapterDAO = BookChapterDAO()
    private let contentDAO = ChapterContentDAO()
    private let readingDataDAO = ReadingDataDAO()
    private let rssDAO = RSSSourceDAO()

    private init() {}

    func makeBackup() throws -> LegadoBackup {
        let books = try bookDAO.getAll()
        let localBookURLs = Set(books.filter { $0.isLocal }.map(\.bookUrl))
        let chapters = try chapterDAO.getAll()
        var localFiles: [String: String] = [:]
        for chapter in chapters {
            let isLocalBook = localBookURLs.contains(chapter.bookUrl)
            let content = FileUtils.getCachedChapterContent(
                bookUrl: chapter.bookUrl,
                chapterIndex: chapter.index
            ) ?? (isLocalBook ? FileUtils.readLocalChapterContent(bookUrl: chapter.bookUrl, chapter: chapter) : nil)
            if let content {
                localFiles[localChapterKey(bookUrl: chapter.bookUrl, index: chapter.index)] = content
            }
        }

        return LegadoBackup(
            version: LegadoBackup.currentVersion,
            createdAt: Date(),
            books: books,
            bookSources: try bookSourceDAO.getAll(),
            chapters: chapters,
            chapterContents: try contentDAO.getAll(),
            bookmarks: try readingDataDAO.getBookmarks(),
            readRecords: try readingDataDAO.getReadRecords(limit: Int.max),
            replaceRules: try readingDataDAO.getReplaceRules(),
            rssSources: try rssDAO.getAllSources(),
            articles: try rssDAO.getAllArticlesForBackup(),
            localChapterFiles: localFiles
        )
    }

    func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(makeBackup())
        try data.write(to: url, options: .atomic)
    }

    func decodeBackup(from url: URL) throws -> LegadoBackup {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(LegadoBackup.self, from: data) else {
            throw BackupError.invalidBackup
        }
        guard backup.version <= LegadoBackup.currentVersion else {
            throw BackupError.unsupportedVersion(backup.version)
        }
        return backup
    }

    func restore(from url: URL) throws {
        let backup = try decodeBackup(from: url)

        // 先通过 decodeBackup 验证完整文件，再修改现有数据。
        try DatabaseManager.shared.clearUserData()
        try bookSourceDAO.saveAll(backup.bookSources)
        try bookDAO.saveAll(backup.books)
        try chapterDAO.saveAll(backup.chapters)
        try contentDAO.saveAll(backup.chapterContents)
        try readingDataDAO.saveBookmarks(backup.bookmarks)
        for record in backup.readRecords {
            try readingDataDAO.saveReadRecord(record)
        }
        try readingDataDAO.saveReplaceRules(backup.replaceRules)
        try rssDAO.saveAll(backup.rssSources)
        try rssDAO.saveAll(backup.articles)

        for (key, content) in backup.localChapterFiles {
            guard let separator = key.range(of: "\u{1F}") else { continue }
            let bookUrl = String(key[..<separator.lowerBound])
            guard let index = Int(key[separator.upperBound...]) else { continue }
            FileUtils.cacheChapterContent(bookUrl: bookUrl, chapterIndex: index, content: content)
        }
    }

    private func localChapterKey(bookUrl: String, index: Int) -> String {
        "\(bookUrl)\u{1F}\(index)"
    }
}
