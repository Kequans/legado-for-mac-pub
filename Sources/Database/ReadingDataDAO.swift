import Foundation
import GRDB

/// 书签、阅读历史和替换规则的数据访问层。
///
/// Android 版把这些数据作为独立表保存，macOS 端也通过独立 DAO 管理，
/// 这样阅读器、设置页和备份功能可以共享同一份持久化数据。
final class ReadingDataDAO {
    private var db: DatabaseQueue? { DatabaseManager.shared.getDatabase() }

    // MARK: - 书签

    func saveBookmark(_ bookmark: Bookmark) throws {
        guard let db else { throw DatabaseError.notInitialized }
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO bookmarks (
                    id, bookUrl, bookName, chapterIndex, chapterPos,
                    chapterName, bookText, content, time
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                bookmark.id.uuidString,
                bookmark.bookUrl,
                bookmark.bookName,
                bookmark.chapterIndex,
                bookmark.chapterPos,
                bookmark.chapterName,
                bookmark.bookText,
                bookmark.content,
                bookmark.time
            ])
        }
    }

    func saveBookmarks(_ bookmarks: [Bookmark]) throws {
        guard let db else { throw DatabaseError.notInitialized }
        try db.write { db in
            for bookmark in bookmarks {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO bookmarks (
                        id, bookUrl, bookName, chapterIndex, chapterPos,
                        chapterName, bookText, content, time
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    bookmark.id.uuidString,
                    bookmark.bookUrl,
                    bookmark.bookName,
                    bookmark.chapterIndex,
                    bookmark.chapterPos,
                    bookmark.chapterName,
                    bookmark.bookText,
                    bookmark.content,
                    bookmark.time
                ])
            }
        }
    }

    func getBookmarks(bookUrl: String? = nil) throws -> [Bookmark] {
        guard let db else { throw DatabaseError.notInitialized }
        return try db.read { db in
            let rows: [Row]
            if let bookUrl {
                rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM bookmarks WHERE bookUrl = ? ORDER BY time DESC
                """, arguments: [bookUrl])
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT * FROM bookmarks ORDER BY time DESC")
            }

            return rows.compactMap { row in
                guard let idString: String = row["id"],
                      let bookUrl: String = row["bookUrl"],
                      let bookName: String = row["bookName"],
                      let chapterName: String = row["chapterName"],
                      let bookText: String = row["bookText"],
                      let content: String = row["content"] else {
                    return nil
                }

                var bookmark = Bookmark(
                    bookUrl: bookUrl,
                    bookName: bookName,
                    chapterIndex: row["chapterIndex"],
                    chapterPos: row["chapterPos"],
                    chapterName: chapterName,
                    bookText: bookText,
                    content: content
                )
                bookmark.id = UUID(uuidString: idString) ?? UUID()
                bookmark.time = row["time"]
                return bookmark
            }
        }
    }

    func deleteBookmark(id: UUID) throws {
        guard let db else { throw DatabaseError.notInitialized }
        try db.write { db in
            try db.execute(sql: "DELETE FROM bookmarks WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func deleteBookmarks(bookUrl: String) throws {
        guard let db else { throw DatabaseError.notInitialized }
        try db.write { db in
            try db.execute(sql: "DELETE FROM bookmarks WHERE bookUrl = ?", arguments: [bookUrl])
        }
    }

    // MARK: - 阅读历史

    func saveReadRecord(_ record: ReadRecord) throws {
        guard let db else { throw DatabaseError.notInitialized }
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO read_records (bookName, readTime, time)
                VALUES (?, ?, ?)
            """, arguments: [record.bookName, record.readTime, record.time])
        }
    }

    func getReadRecords(limit: Int = 200) throws -> [ReadRecord] {
        guard let db else { throw DatabaseError.notInitialized }
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM read_records ORDER BY time DESC LIMIT ?
            """, arguments: [max(1, limit)])
            return rows.compactMap { row in
                guard let bookName: String = row["bookName"] else { return nil }
                return ReadRecord(
                    bookName: bookName,
                    readTime: row["readTime"]
                ).with(time: row["time"])
            }
        }
    }

    // MARK: - 替换规则

    func saveReplaceRule(_ rule: ReplaceRule) throws {
        guard let db else { throw DatabaseError.notInitialized }
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO replace_rules (
                    id, name, "group", pattern, replacement, "order", enabled, isRegex, scope
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                rule.id.uuidString,
                rule.name,
                rule.group,
                rule.pattern,
                rule.replacement,
                rule.order,
                rule.enabled,
                rule.isRegex,
                rule.scope
            ])
        }
    }

    func saveReplaceRules(_ rules: [ReplaceRule]) throws {
        guard let db else { throw DatabaseError.notInitialized }
        try db.write { db in
            for rule in rules {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO replace_rules (
                        id, name, "group", pattern, replacement, "order", enabled, isRegex, scope
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    rule.id.uuidString,
                    rule.name,
                    rule.group,
                    rule.pattern,
                    rule.replacement,
                    rule.order,
                    rule.enabled,
                    rule.isRegex,
                    rule.scope
                ])
            }
        }
    }

    func getReplaceRules() throws -> [ReplaceRule] {
        guard let db else { throw DatabaseError.notInitialized }
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM replace_rules ORDER BY \"order\", name")
            return rows.compactMap { row in
                guard let name: String = row["name"],
                      let pattern: String = row["pattern"],
                      let replacement: String = row["replacement"] else {
                    return nil
                }

                var rule = ReplaceRule(name: name, pattern: pattern, replacement: replacement)
                if let id: String = row["id"] {
                    rule.id = UUID(uuidString: id) ?? UUID()
                }
                rule.group = row["group"]
                rule.order = row["order"]
                rule.enabled = row["enabled"]
                rule.isRegex = row["isRegex"]
                rule.scope = row["scope"]
                return rule
            }
        }
    }

    func deleteReplaceRule(id: UUID) throws {
        guard let db else { throw DatabaseError.notInitialized }
        try db.write { db in
            try db.execute(sql: "DELETE FROM replace_rules WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// 按 Legado 的作用域规则应用全局净化规则。
    func applyReplaceRules(to content: String, bookUrl: String? = nil) -> String {
        guard !content.isEmpty, let rules = try? getReplaceRules() else { return content }
        var result = content

        for rule in rules where rule.enabled {
            if let scope = rule.scope?.trimmingCharacters(in: .whitespacesAndNewlines),
               !scope.isEmpty,
               scope != "*",
               scope != "all",
               scope != bookUrl {
                continue
            }

            if rule.isRegex {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.dotMatchesLineSeparators]) else {
                    continue
                }
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(location: 0, length: result.utf16.count),
                    withTemplate: rule.replacement
                )
            } else {
                result = result.replacingOccurrences(of: rule.pattern, with: rule.replacement)
            }
        }

        return result
    }
}

private extension ReadRecord {
    func with(time: Int64) -> ReadRecord {
        var copy = self
        copy.time = time
        return copy
    }
}
