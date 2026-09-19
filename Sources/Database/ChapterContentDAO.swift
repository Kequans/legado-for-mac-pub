import Foundation
import GRDB

/// 章节内容缓存数据访问对象
class ChapterContentDAO {
    private var db: DatabaseQueue? { DatabaseManager.shared.getDatabase() }
    
    /// 保存章节内容
    func save(_ content: ChapterContent) throws {
        try db?.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO chapter_contents (
                    chapterUrl, bookUrl, content, cachedTime
                ) VALUES (?, ?, ?, ?)
            """, arguments: [
                content.chapterUrl, content.bookUrl, content.content, content.cachedTime
            ])
        }
    }
    
    /// 批量保存章节内容
    func saveAll(_ contents: [ChapterContent]) throws {
        try db?.write { db in
            for content in contents {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO chapter_contents (
                        chapterUrl, bookUrl, content, cachedTime
                    ) VALUES (?, ?, ?, ?)
                """, arguments: [
                    content.chapterUrl, content.bookUrl, content.content, content.cachedTime
                ])
            }
        }
    }
    
    /// 获取章节内容
    func get(chapterUrl: String) throws -> ChapterContent? {
        guard let db = db else { return nil }
        return try db.read { db in
            try ChapterContent.fetchOne(db, sql: """
                SELECT * FROM chapter_contents WHERE chapterUrl = ?
            """, arguments: [chapterUrl])
        }
    }

    /// 获取全部章节缓存，用于备份和迁移。
    func getAll() throws -> [ChapterContent] {
        guard let db else { return [] }
        return try db.read { db in
            try ChapterContent.fetchAll(db, sql: "SELECT * FROM chapter_contents ORDER BY bookUrl, cachedTime")
        }
    }
    
    /// 检查章节是否已缓存
    func isCached(chapterUrl: String) throws -> Bool {
        return try get(chapterUrl: chapterUrl) != nil
    }
    
    /// 删除书籍的所有缓存内容
    func deleteContents(bookUrl: String) throws {
        try db?.write { db in
            try db.execute(sql: "DELETE FROM chapter_contents WHERE bookUrl = ?", arguments: [bookUrl])
        }
    }
    
    /// 清理过期缓存（超过30天）
    func cleanExpiredCache() throws {
        let thirtyDaysAgo = Int64(Date().timeIntervalSince1970) - (30 * 24 * 3600)
        try db?.write { db in
            try db.execute(sql: "DELETE FROM chapter_contents WHERE cachedTime < ?", arguments: [thirtyDaysAgo])
        }
    }
    
    /// 获取缓存统计
    func getCacheStats(bookUrl: String) throws -> (total: Int, cached: Int) {
        guard let db = db else { return (0, 0) }
        return try db.read { db in
            let total = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM book_chapters WHERE bookUrl = ?
            """, arguments: [bookUrl]) ?? 0
            
            let cached = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM chapter_contents WHERE bookUrl = ?
            """, arguments: [bookUrl]) ?? 0
            
            return (total, cached)
        }
    }
}

// MARK: - ChapterContent GRDB 扩展
extension ChapterContent: FetchableRecord, PersistableRecord {
    init(row: Row) {
        self.chapterUrl = row["chapterUrl"]
        self.bookUrl = row["bookUrl"]
        self.content = row["content"]
        self.cachedTime = row["cachedTime"]
    }
    
    func encode(to container: inout PersistenceContainer) {
        container["chapterUrl"] = chapterUrl
        container["bookUrl"] = bookUrl
        container["content"] = content
        container["cachedTime"] = cachedTime
    }
}
