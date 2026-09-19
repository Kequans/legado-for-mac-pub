import Foundation
import GRDB

/// 书籍数据访问对象
class BookDAO {
    private var db: DatabaseQueue? { DatabaseManager.shared.getDatabase() }
    
    // 插入或更新书籍
    func save(_ book: Book) throws {
        guard let db else { throw DatabaseError.notInitialized }
        try db.write { db in
            // 使用 UPSERT 保留单条书籍记录的完整字段。旧实现只更新了少数列，
            // 网络刷新后会丢失自定义简介、标签、封面和排序信息。
            try db.execute(sql: """
                INSERT INTO books (
                    bookUrl, tocUrl, origin, originName, name, author,
                    kind, customTag, coverUrl, customCoverUrl, localCoverPath, intro, customIntro,
                    type, "group", latestChapterTitle, latestChapterTime,
                    lastCheckTime, lastCheckCount, totalChapterNum,
                    durChapterTitle, durChapterIndex, durChapterPos, durChapterTime,
                    wordCount, canUpdate, "order", originOrder, variable, skipDetailPage
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(bookUrl) DO UPDATE SET
                    tocUrl = excluded.tocUrl,
                    origin = excluded.origin,
                    originName = excluded.originName,
                    name = excluded.name,
                    author = excluded.author,
                    kind = excluded.kind,
                    customTag = excluded.customTag,
                    coverUrl = excluded.coverUrl,
                    customCoverUrl = excluded.customCoverUrl,
                    localCoverPath = excluded.localCoverPath,
                    intro = excluded.intro,
                    customIntro = excluded.customIntro,
                    type = excluded.type,
                    "group" = excluded."group",
                    latestChapterTitle = excluded.latestChapterTitle,
                    latestChapterTime = excluded.latestChapterTime,
                    lastCheckTime = excluded.lastCheckTime,
                    lastCheckCount = excluded.lastCheckCount,
                    totalChapterNum = excluded.totalChapterNum,
                    durChapterTitle = excluded.durChapterTitle,
                    durChapterIndex = excluded.durChapterIndex,
                    durChapterPos = excluded.durChapterPos,
                    durChapterTime = excluded.durChapterTime,
                    wordCount = excluded.wordCount,
                    canUpdate = excluded.canUpdate,
                    "order" = excluded."order",
                    originOrder = excluded.originOrder,
                    variable = excluded.variable,
                    skipDetailPage = excluded.skipDetailPage
            """, arguments: [
                book.bookUrl, book.tocUrl, book.origin, book.originName,
                book.name, book.author, book.kind, book.customTag,
                book.coverUrl, book.customCoverUrl, book.localCoverPath, book.intro, book.customIntro,
                book.type.rawValue, book.group, book.latestChapterTitle, book.latestChapterTime,
                book.lastCheckTime, book.lastCheckCount, book.totalChapterNum,
                book.durChapterTitle, book.durChapterIndex, book.durChapterPos, book.durChapterTime,
                book.wordCount, book.canUpdate, book.order, book.originOrder, book.variable, book.skipDetailPage
            ])
        }
    }

    func saveAll(_ books: [Book]) throws {
        guard let db else { throw DatabaseError.notInitialized }
        try db.write { db in
            for book in books {
                try db.execute(sql: """
                    INSERT INTO books (
                        bookUrl, tocUrl, origin, originName, name, author,
                        kind, customTag, coverUrl, customCoverUrl, localCoverPath, intro, customIntro,
                        type, "group", latestChapterTitle, latestChapterTime,
                        lastCheckTime, lastCheckCount, totalChapterNum,
                        durChapterTitle, durChapterIndex, durChapterPos, durChapterTime,
                        wordCount, canUpdate, "order", originOrder, variable, skipDetailPage
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(bookUrl) DO UPDATE SET
                        tocUrl = excluded.tocUrl, origin = excluded.origin, originName = excluded.originName,
                        name = excluded.name, author = excluded.author, kind = excluded.kind,
                        customTag = excluded.customTag, coverUrl = excluded.coverUrl,
                        customCoverUrl = excluded.customCoverUrl, localCoverPath = excluded.localCoverPath,
                        intro = excluded.intro, customIntro = excluded.customIntro, type = excluded.type,
                        "group" = excluded."group", latestChapterTitle = excluded.latestChapterTitle,
                        latestChapterTime = excluded.latestChapterTime, lastCheckTime = excluded.lastCheckTime,
                        lastCheckCount = excluded.lastCheckCount, totalChapterNum = excluded.totalChapterNum,
                        durChapterTitle = excluded.durChapterTitle, durChapterIndex = excluded.durChapterIndex,
                        durChapterPos = excluded.durChapterPos, durChapterTime = excluded.durChapterTime,
                        wordCount = excluded.wordCount, canUpdate = excluded.canUpdate,
                        "order" = excluded."order", originOrder = excluded.originOrder,
                        variable = excluded.variable, skipDetailPage = excluded.skipDetailPage
                """, arguments: [
                    book.bookUrl, book.tocUrl, book.origin, book.originName, book.name, book.author,
                    book.kind, book.customTag, book.coverUrl, book.customCoverUrl, book.localCoverPath,
                    book.intro, book.customIntro, book.type.rawValue, book.group,
                    book.latestChapterTitle, book.latestChapterTime, book.lastCheckTime,
                    book.lastCheckCount, book.totalChapterNum, book.durChapterTitle,
                    book.durChapterIndex, book.durChapterPos, book.durChapterTime, book.wordCount,
                    book.canUpdate, book.order, book.originOrder, book.variable, book.skipDetailPage
                ])
            }
        }
    }
    
    // 获取所有书籍
    func getAll() throws -> [Book] {
        guard let db = db else { return [] }
        return try db.read { db in
            try Book.fetchAll(db, sql: "SELECT * FROM books ORDER BY lastCheckTime DESC")
        }
    }
    
    // 根据URL获取书籍
    func get(bookUrl: String) throws -> Book? {
        guard let db = db else { return nil }
        return try db.read { db in
            try Book.fetchOne(db, sql: "SELECT * FROM books WHERE bookUrl = ?", arguments: [bookUrl])
        }
    }
    
    // 删除书籍
    func delete(bookUrl: String) throws {
        try db?.write { db in
            try db.execute(sql: "DELETE FROM books WHERE bookUrl = ?", arguments: [bookUrl])
        }
    }
    
    // 获取最近阅读的书籍
    func getLastRead() throws -> Book? {
        guard let db = db else { return nil }
        return try db.read { db in
            try Book.fetchOne(db, sql: "SELECT * FROM books ORDER BY durChapterTime DESC LIMIT 1")
        }
    }
}

// MARK: - Book GRDB 扩展
extension Book: FetchableRecord, PersistableRecord {
    enum Columns {
        static let bookUrl = Column("bookUrl")
        static let name = Column("name")
        static let author = Column("author")
    }
    
    init(row: Row) {
        self.bookUrl = row["bookUrl"]
        self.tocUrl = row["tocUrl"]
        self.origin = row["origin"]
        self.originName = row["originName"]
        self.name = row["name"]
        self.author = row["author"]
        self.kind = row["kind"]
        self.customTag = row["customTag"]
        self.coverUrl = row["coverUrl"]
        self.customCoverUrl = row["customCoverUrl"]
        self.localCoverPath = row["localCoverPath"]
        self.intro = row["intro"]
        self.customIntro = row["customIntro"]
        self.type = BookType(rawValue: row["type"]) ?? .text
        self.group = row["group"]
        self.latestChapterTitle = row["latestChapterTitle"]
        self.latestChapterTime = row["latestChapterTime"]
        self.lastCheckTime = row["lastCheckTime"]
        self.lastCheckCount = row["lastCheckCount"]
        self.totalChapterNum = row["totalChapterNum"]
        self.durChapterTitle = row["durChapterTitle"]
        self.durChapterIndex = row["durChapterIndex"]
        self.durChapterPos = row["durChapterPos"]
        self.durChapterTime = row["durChapterTime"]
        self.wordCount = row["wordCount"]
        self.canUpdate = row["canUpdate"]
        self.order = row["order"]
        self.originOrder = row["originOrder"]
        self.variable = row["variable"]
        self.skipDetailPage = row["skipDetailPage"]
    }
    
    func encode(to container: inout PersistenceContainer) {
        container["bookUrl"] = bookUrl
        container["tocUrl"] = tocUrl
        container["origin"] = origin
        container["originName"] = originName
        container["name"] = name
        container["author"] = author
        container["kind"] = kind
        container["customTag"] = customTag
        container["coverUrl"] = coverUrl
        container["customCoverUrl"] = customCoverUrl
        container["localCoverPath"] = localCoverPath
        container["intro"] = intro
        container["customIntro"] = customIntro
        container["type"] = type.rawValue
        container["group"] = group
        container["latestChapterTitle"] = latestChapterTitle
        container["latestChapterTime"] = latestChapterTime
        container["lastCheckTime"] = lastCheckTime
        container["lastCheckCount"] = lastCheckCount
        container["totalChapterNum"] = totalChapterNum
        container["durChapterTitle"] = durChapterTitle
        container["durChapterIndex"] = durChapterIndex
        container["durChapterPos"] = durChapterPos
        container["durChapterTime"] = durChapterTime
        container["wordCount"] = wordCount
        container["canUpdate"] = canUpdate
        container["order"] = order
        container["originOrder"] = originOrder
        container["variable"] = variable
        container["skipDetailPage"] = skipDetailPage
    }
}
