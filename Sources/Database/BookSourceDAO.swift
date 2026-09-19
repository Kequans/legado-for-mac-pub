import Foundation
import GRDB

/// 书源数据访问对象
class BookSourceDAO {
    private var db: DatabaseQueue? { DatabaseManager.shared.getDatabase() }
    
    // 保存书源
    func save(_ bookSource: BookSource) throws {
        try db?.write { db in
            let encoder = JSONEncoder()
            
            // 将规则对象转换为JSON字符串
            let ruleExploreJson = try? encoder.encode(bookSource.ruleExplore)
            let ruleSearchJson = try? encoder.encode(bookSource.ruleSearch)
            let ruleBookInfoJson = try? encoder.encode(bookSource.ruleBookInfo)
            let ruleTocJson = try? encoder.encode(bookSource.ruleToc)
            let ruleContentJson = try? encoder.encode(bookSource.ruleContent)
            let ruleReviewJson = try? encoder.encode(bookSource.ruleReview)
            
            try db.execute(sql: """
                INSERT OR REPLACE INTO book_sources (
                    bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType,
                    bookUrlPattern, customOrder, enabled, enabledExplore,
                    header, loginUrl, loginUi, loginCheckJs, coverDecodeJs,
                    concurrentRate, enabledCookieJar, jsLib, bookSourceComment,
                    variableComment, lastUpdateTime, respondTime, weight,
                    exploreUrl, exploreScreen, ruleExplore,
                    searchUrl, ruleSearch, ruleBookInfo, ruleToc, ruleContent, ruleReview
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                bookSource.bookSourceUrl, bookSource.bookSourceName, bookSource.bookSourceGroup,
                bookSource.bookSourceType, bookSource.bookUrlPattern, bookSource.customOrder,
                bookSource.enabled, bookSource.enabledExplore, bookSource.header,
                bookSource.loginUrl, bookSource.loginUi, bookSource.loginCheckJs,
                bookSource.coverDecodeJs, bookSource.concurrentRate, bookSource.enabledCookieJar,
                bookSource.jsLib, bookSource.bookSourceComment, bookSource.variableComment,
                bookSource.lastUpdateTime, bookSource.respondTime, bookSource.weight,
                bookSource.exploreUrl, bookSource.exploreScreen,
                ruleExploreJson.flatMap { String(data: $0, encoding: .utf8) },
                bookSource.searchUrl,
                ruleSearchJson.flatMap { String(data: $0, encoding: .utf8) },
                ruleBookInfoJson.flatMap { String(data: $0, encoding: .utf8) },
                ruleTocJson.flatMap { String(data: $0, encoding: .utf8) },
                ruleContentJson.flatMap { String(data: $0, encoding: .utf8) },
                ruleReviewJson.flatMap { String(data: $0, encoding: .utf8) }
            ])
        }
    }
    
    // 批量保存书源
    func saveAll(_ bookSources: [BookSource]) throws {
        for bookSource in bookSources {
            try save(bookSource)
        }
    }
    
    // 获取所有书源
    func getAll() throws -> [BookSource] {
        guard let db = db else { return [] }
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM book_sources ORDER BY customOrder, bookSourceName")
            return rows.compactMap { row in
                try? decodeBookSource(from: row)
            }
        }
    }
    
    // 获取启用的书源
    func getEnabled() throws -> [BookSource] {
        guard let db = db else { return [] }
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM book_sources WHERE enabled = 1 ORDER BY customOrder, bookSourceName")
            return rows.compactMap { row in
                try? decodeBookSource(from: row)
            }
        }
    }
    
    // 根据URL获取书源
    func get(bookSourceUrl: String) throws -> BookSource? {
        guard let db = db else { return nil }
        return try db.read { db in
            if let row = try Row.fetchOne(db, sql: "SELECT * FROM book_sources WHERE bookSourceUrl = ?", arguments: [bookSourceUrl]) {
                return try? decodeBookSource(from: row)
            }
            return nil
        }
    }
    
    // 删除书源
    func delete(bookSourceUrl: String) throws {
        try db?.write { db in
            try db.execute(sql: "DELETE FROM book_sources WHERE bookSourceUrl = ?", arguments: [bookSourceUrl])
        }
    }
    
    // 更新启用状态
    func updateEnabled(bookSourceUrl: String, enabled: Bool) throws {
        try db?.write { db in
            try db.execute(sql: "UPDATE book_sources SET enabled = ? WHERE bookSourceUrl = ?", arguments: [enabled, bookSourceUrl])
        }
    }
    
    // 解码书源
    private func decodeBookSource(from row: Row) throws -> BookSource {
        let decoder = JSONDecoder()
        
        var bookSource = BookSource(
            bookSourceUrl: row["bookSourceUrl"],
            bookSourceName: row["bookSourceName"]
        )
        
        bookSource.bookSourceGroup = row["bookSourceGroup"]
        bookSource.bookSourceType = row["bookSourceType"]
        bookSource.bookUrlPattern = row["bookUrlPattern"]
        bookSource.customOrder = row["customOrder"]
        bookSource.enabled = row["enabled"]
        bookSource.enabledExplore = row["enabledExplore"]
        bookSource.header = row["header"]
        bookSource.loginUrl = row["loginUrl"]
        bookSource.loginUi = row["loginUi"]
        bookSource.loginCheckJs = row["loginCheckJs"]
        bookSource.coverDecodeJs = row["coverDecodeJs"]
        bookSource.concurrentRate = row["concurrentRate"]
        bookSource.enabledCookieJar = row["enabledCookieJar"]
        bookSource.jsLib = row["jsLib"]
        bookSource.bookSourceComment = row["bookSourceComment"]
        bookSource.variableComment = row["variableComment"]
        bookSource.lastUpdateTime = row["lastUpdateTime"]
        bookSource.respondTime = row["respondTime"]
        bookSource.weight = row["weight"]
        bookSource.exploreUrl = row["exploreUrl"]
        bookSource.exploreScreen = row["exploreScreen"]
        bookSource.searchUrl = row["searchUrl"]
        
        // 解码规则
        if let ruleExploreStr: String = row["ruleExplore"],
           let data = ruleExploreStr.data(using: .utf8) {
            bookSource.ruleExplore = try? decoder.decode(ExploreRule.self, from: data)
        }
        
        if let ruleSearchStr: String = row["ruleSearch"],
           let data = ruleSearchStr.data(using: .utf8) {
            bookSource.ruleSearch = try? decoder.decode(SearchRule.self, from: data)
        }
        
        if let ruleBookInfoStr: String = row["ruleBookInfo"],
           let data = ruleBookInfoStr.data(using: .utf8) {
            bookSource.ruleBookInfo = try? decoder.decode(BookInfoRule.self, from: data)
        }
        
        if let ruleTocStr: String = row["ruleToc"],
           let data = ruleTocStr.data(using: .utf8) {
            bookSource.ruleToc = try? decoder.decode(TocRule.self, from: data)
        }
        
        if let ruleContentStr: String = row["ruleContent"],
           let data = ruleContentStr.data(using: .utf8) {
            bookSource.ruleContent = try? decoder.decode(ContentRule.self, from: data)
        }
        
        if let ruleReviewStr: String = row["ruleReview"],
           let data = ruleReviewStr.data(using: .utf8) {
            bookSource.ruleReview = try? decoder.decode(ReviewRule.self, from: data)
        }
        
        return bookSource
    }
}
