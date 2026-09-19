import Foundation
import GRDB

/// 章节数据访问对象
class BookChapterDAO {
    private var db: DatabaseQueue? { DatabaseManager.shared.getDatabase() }
    
    // 保存章节
    func save(_ chapter: BookChapter) throws {
        try db?.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO book_chapters (
                    url, title, bookUrl, "index", isVip, isPay,
                    resourceUrl, tag, start, end, variable,
                    startFragmentId, endFragmentId
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                chapter.url, chapter.title, chapter.bookUrl, chapter.index,
                chapter.isVip, chapter.isPay, chapter.resourceUrl, chapter.tag,
                chapter.start, chapter.end, chapter.variable,
                chapter.startFragmentId, chapter.endFragmentId
            ])
        }
    }
    
    // 批量保存章节
    func saveAll(_ chapters: [BookChapter]) throws {
        try db?.write { db in
            for chapter in chapters {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO book_chapters (
                        url, title, bookUrl, "index", isVip, isPay,
                        resourceUrl, tag, start, end, variable,
                        startFragmentId, endFragmentId
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    chapter.url, chapter.title, chapter.bookUrl, chapter.index,
                    chapter.isVip, chapter.isPay, chapter.resourceUrl, chapter.tag,
                    chapter.start, chapter.end, chapter.variable,
                    chapter.startFragmentId, chapter.endFragmentId
                ])
            }
        }
    }
    
    // 获取书籍的所有章节
    func getChapters(bookUrl: String) throws -> [BookChapter] {
        guard let db = db else { return [] }
        return try db.read { db in
            try BookChapter.fetchAll(db, sql: """
                SELECT * FROM book_chapters 
                WHERE bookUrl = ? 
                ORDER BY "index"
            """, arguments: [bookUrl])
        }
    }

    /// 获取数据库中的全部章节，用于备份和数据迁移。
    func getAll() throws -> [BookChapter] {
        guard let db else { return [] }
        return try db.read { db in
            try BookChapter.fetchAll(db, sql: "SELECT * FROM book_chapters ORDER BY bookUrl, \"index\"")
        }
    }
    
    // 获取指定章节
    func get(url: String) throws -> BookChapter? {
        guard let db = db else { return nil }
        return try db.read { db in
            try BookChapter.fetchOne(db, sql: "SELECT * FROM book_chapters WHERE url = ?", arguments: [url])
        }
    }
    
    // 删除书籍的所有章节
    func deleteChapters(bookUrl: String) throws {
        try db?.write { db in
            try db.execute(sql: "DELETE FROM book_chapters WHERE bookUrl = ?", arguments: [bookUrl])
        }
    }
    
    // 获取章节数量
    func getChapterCount(bookUrl: String) throws -> Int {
        guard let db = db else { return 0 }
        return try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM book_chapters WHERE bookUrl = ?", arguments: [bookUrl]) ?? 0
        }
    }
}

// MARK: - BookChapter GRDB 扩展
extension BookChapter: FetchableRecord, PersistableRecord {
    init(row: Row) {
        self.url = row["url"]
        self.title = row["title"]
        self.bookUrl = row["bookUrl"]
        self.index = row["index"]
        self.isVip = row["isVip"]
        self.isPay = row["isPay"]
        self.resourceUrl = row["resourceUrl"]
        self.tag = row["tag"]
        self.start = row["start"]
        self.end = row["end"]
        self.variable = row["variable"]
        self.startFragmentId = row["startFragmentId"]
        self.endFragmentId = row["endFragmentId"]
    }
    
    func encode(to container: inout PersistenceContainer) {
        container["url"] = url
        container["title"] = title
        container["bookUrl"] = bookUrl
        container["index"] = index
        container["isVip"] = isVip
        container["isPay"] = isPay
        container["resourceUrl"] = resourceUrl
        container["tag"] = tag
        container["start"] = start
        container["end"] = end
        container["variable"] = variable
        container["startFragmentId"] = startFragmentId
        container["endFragmentId"] = endFragmentId
    }
}
