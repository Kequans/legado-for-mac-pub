import Foundation
import GRDB

/// 数据库管理器
class DatabaseManager {
    static let shared = DatabaseManager()
    private var dbQueue: DatabaseQueue?
    private(set) var databaseURL: URL?
    
    private init() {}
    
    // 初始化数据库
    func initialize() {
        if dbQueue != nil { return }
        do {
            let fileManager = Foundation.FileManager()
            let appSupportURL = try fileManager.url(
                for: Foundation.FileManager.SearchPathDirectory.applicationSupportDirectory,
                in: Foundation.FileManager.SearchPathDomainMask.userDomainMask,
                appropriateFor: nil,
                create: true
            )
            
            let legadoURL = appSupportURL.appendingPathComponent("Legado", isDirectory: true)
            try fileManager.createDirectory(at: legadoURL, withIntermediateDirectories: true)
            
            let dbURL = legadoURL.appendingPathComponent("legado.db")
            dbQueue = try DatabaseQueue(path: dbURL.path)
            databaseURL = dbURL
            
            try createTables()
            try migrateDatabase()
            print("数据库初始化成功: \(dbURL.path)")
        } catch {
            print("数据库初始化失败: \(error)")
        }
    }
    
    // 创建表
    private func createTables() throws {
        try dbQueue?.write { db in
            // 书籍表
            try db.create(table: "books", ifNotExists: true) { t in
                t.column("bookUrl", .text).primaryKey()
                t.column("tocUrl", .text).notNull().defaults(to: "")
                t.column("origin", .text).notNull().defaults(to: "local")
                t.column("originName", .text).notNull().defaults(to: "")
                t.column("name", .text).notNull()
                t.column("author", .text).notNull()
                t.column("kind", .text)
                t.column("customTag", .text)
                t.column("coverUrl", .text)
                t.column("customCoverUrl", .text)
                t.column("localCoverPath", .text)
                t.column("intro", .text)
                t.column("customIntro", .text)
                t.column("type", .integer).notNull().defaults(to: 0)
                t.column("group", .integer).notNull().defaults(to: 0)
                t.column("latestChapterTitle", .text)
                t.column("latestChapterTime", .integer).notNull().defaults(to: 0)
                t.column("lastCheckTime", .integer).notNull().defaults(to: 0)
                t.column("lastCheckCount", .integer).notNull().defaults(to: 0)
                t.column("totalChapterNum", .integer).notNull().defaults(to: 0)
                t.column("durChapterTitle", .text)
                t.column("durChapterIndex", .integer).notNull().defaults(to: 0)
                t.column("durChapterPos", .integer).notNull().defaults(to: 0)
                t.column("durChapterTime", .integer).notNull().defaults(to: 0)
                t.column("wordCount", .text)
                t.column("canUpdate", .boolean).notNull().defaults(to: true)
                t.column("order", .integer).notNull().defaults(to: 0)
                t.column("originOrder", .integer).notNull().defaults(to: 0)
                t.column("variable", .text)
                t.column("skipDetailPage", .boolean).notNull().defaults(to: false)
            }
            
            // 书源表
            try db.create(table: "book_sources", ifNotExists: true) { t in
                t.column("bookSourceUrl", .text).primaryKey()
                t.column("bookSourceName", .text).notNull()
                t.column("bookSourceGroup", .text)
                t.column("bookSourceType", .integer).notNull().defaults(to: 0)
                t.column("bookUrlPattern", .text)
                t.column("customOrder", .integer).notNull().defaults(to: 0)
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("enabledExplore", .boolean).notNull().defaults(to: true)
                t.column("header", .text)
                t.column("loginUrl", .text)
                t.column("loginUi", .text)
                t.column("loginCheckJs", .text)
                t.column("coverDecodeJs", .text)
                t.column("concurrentRate", .text)
                t.column("enabledCookieJar", .boolean).notNull().defaults(to: true)
                t.column("jsLib", .text)
                t.column("bookSourceComment", .text)
                t.column("variableComment", .text)
                t.column("lastUpdateTime", .integer).notNull().defaults(to: 0)
                t.column("respondTime", .integer).notNull().defaults(to: 180000)
                t.column("weight", .integer).notNull().defaults(to: 0)
                t.column("exploreUrl", .text)
                t.column("exploreScreen", .text)
                t.column("ruleExplore", .text)
                t.column("searchUrl", .text)
                t.column("ruleSearch", .text)
                t.column("ruleBookInfo", .text)
                t.column("ruleToc", .text)
                t.column("ruleContent", .text)
                t.column("ruleReview", .text)
            }
            
            // 章节表
            try db.create(table: "book_chapters", ifNotExists: true) { t in
                t.column("url", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("bookUrl", .text).notNull().indexed()
                t.column("index", .integer).notNull()
                t.column("isVip", .boolean).notNull().defaults(to: false)
                t.column("isPay", .boolean).notNull().defaults(to: false)
                t.column("resourceUrl", .text)
                t.column("tag", .text)
                t.column("start", .integer)
                t.column("end", .integer)
                t.column("variable", .text)
                t.column("startFragmentId", .text)
                t.column("endFragmentId", .text)
            }
            
            // 书签表
            try db.create(table: "bookmarks", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("bookUrl", .text).notNull().indexed()
                t.column("bookName", .text).notNull()
                t.column("chapterIndex", .integer).notNull()
                t.column("chapterPos", .integer).notNull()
                t.column("chapterName", .text).notNull()
                t.column("bookText", .text).notNull()
                t.column("content", .text).notNull()
                t.column("time", .integer).notNull()
            }
            
            // 替换规则表
            try db.create(table: "replace_rules", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("group", .text)
                t.column("pattern", .text).notNull()
                t.column("replacement", .text).notNull()
                t.column("order", .integer).notNull().defaults(to: 0)
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("isRegex", .boolean).notNull().defaults(to: true)
                t.column("scope", .text)
            }
            
            // 阅读记录表
            try db.create(table: "read_records", ifNotExists: true) { t in
                t.column("bookName", .text).notNull()
                t.column("readTime", .integer).notNull()
                t.column("time", .integer).notNull()
                t.primaryKey(["bookName", "time"])
            }
            
            // 章节内容缓存表
            try db.create(table: "chapter_contents", ifNotExists: true) { t in
                t.column("chapterUrl", .text).primaryKey()
                t.column("bookUrl", .text).notNull().indexed()
                t.column("content", .text).notNull()
                t.column("cachedTime", .integer).notNull()
            }

            // 订阅源表
            try db.create(table: "rss_sources", ifNotExists: true) { t in
                t.column("sourceUrl", .text).primaryKey()
                t.column("sourceName", .text).notNull()
                t.column("sourceIcon", .text)
                t.column("sourceGroup", .text)
                t.column("enabled", .boolean).notNull().defaults(to: true)
                t.column("enableJs", .boolean).notNull().defaults(to: false)
                t.column("enabledCookieJar", .boolean).notNull().defaults(to: false)
                t.column("customOrder", .integer).notNull().defaults(to: 0)
                t.column("lastUpdateTime", .integer).notNull().defaults(to: 0)
                t.column("ruleArticles", .text)
                t.column("ruleNextUrl", .text)
                t.column("ruleTitle", .text)
                t.column("ruleLink", .text)
                t.column("ruleDescription", .text)
                t.column("ruleContent", .text)
                t.column("ruleImage", .text)
                t.column("rulePubDate", .text)
                t.column("header", .text)
                t.column("articleStyle", .integer).notNull().defaults(to: 0)
                t.column("singleUrl", .boolean).notNull().defaults(to: false)
                t.column("sortUrl", .text)
                t.column("loadWithBaseUrl", .boolean).notNull().defaults(to: false)
            }

            // 文章表
            try db.create(table: "articles", ifNotExists: true) { t in
                t.column("link", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("sourceUrl", .text).notNull().indexed()
                t.column("description", .text)
                t.column("content", .text)
                t.column("imageUrl", .text)
                t.column("pubDate", .integer)
                t.column("isRead", .boolean).notNull().defaults(to: false)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("readTime", .integer)
                t.foreignKey(["sourceUrl"], references: "rss_sources", columns: ["sourceUrl"], onDelete: .cascade)
            }
        }
    }
    
    // 数据库迁移
    private func migrateDatabase() throws {
        try dbQueue?.write { db in
            // 检查并添加skipDetailPage列（如果不存在）
            if try !db.columns(in: "books").contains(where: { $0.name == "skipDetailPage" }) {
                try db.execute(sql: """
                    ALTER TABLE books ADD COLUMN skipDetailPage BOOLEAN NOT NULL DEFAULT 0
                """)
                print("✅ 数据库迁移：添加 skipDetailPage 列")
            }
        }
    }
    
    // 获取数据库连接
    func getDatabase() -> DatabaseQueue? {
        return dbQueue
    }

    var isInitialized: Bool { dbQueue != nil }

    /// 应用数据所在目录，供备份和本地书籍导入使用。
    var dataDirectoryURL: URL? {
        databaseURL?.deletingLastPathComponent()
    }

    /// 清空可由用户重新生成的数据。
    /// 备份恢复会先验证备份文件，再在一个事务中调用此方法。
    func clearUserData() throws {
        guard let dbQueue else { throw DatabaseError.notInitialized }
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM articles")
            try db.execute(sql: "DELETE FROM rss_sources")
            try db.execute(sql: "DELETE FROM chapter_contents")
            try db.execute(sql: "DELETE FROM book_chapters")
            try db.execute(sql: "DELETE FROM bookmarks")
            try db.execute(sql: "DELETE FROM read_records")
            try db.execute(sql: "DELETE FROM replace_rules")
            try db.execute(sql: "DELETE FROM books")
            try db.execute(sql: "DELETE FROM book_sources")
        }
    }
}
