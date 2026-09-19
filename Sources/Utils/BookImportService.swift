import Foundation

enum BookImportService {
    static func decodeBooks(from data: Data) throws -> [Book] {
        let decoder = JSONDecoder()
        if let books = try? decoder.decode([Book].self, from: data) { return books }
        if let book = try? decoder.decode(Book.self, from: data) { return [book] }
        if let backup = try? decoder.decode(LegadoBackup.self, from: data) { return backup.books }

        let json = try JSONSerialization.jsonObject(with: data)
        if let container = json as? [String: Any], let value = container["books"] {
            return try decodeDictionaries(value)
        }
        return try decodeDictionaries(json)
    }

    private static func decodeDictionaries(_ value: Any) throws -> [Book] {
        let dictionaries: [[String: Any]]
        if let array = value as? [[String: Any]] {
            dictionaries = array
        } else if let dictionary = value as? [String: Any] {
            dictionaries = [dictionary]
        } else {
            throw error
        }

        let books = dictionaries.compactMap(makeBook)
        guard !books.isEmpty else { throw error }
        return books
    }

    private static func makeBook(_ json: [String: Any]) -> Book? {
        guard let bookUrl = string(json, keys: ["bookUrl", "book_url"]), !bookUrl.isEmpty else { return nil }
        let name = string(json, keys: ["name", "bookName", "book_name"]) ?? "未命名书籍"
        let author = string(json, keys: ["author", "bookAuthor", "book_author"]) ?? "未知作者"
        var book = Book(bookUrl: bookUrl, name: name, author: author)
        book.tocUrl = string(json, keys: ["tocUrl", "toc_url"]) ?? ""
        book.origin = string(json, keys: ["origin"]) ?? "local"
        book.originName = string(json, keys: ["originName", "origin_name"]) ?? ""
        book.kind = string(json, keys: ["kind"])
        book.customTag = string(json, keys: ["customTag", "custom_tag"])
        book.coverUrl = string(json, keys: ["coverUrl", "cover_url"])
        book.customCoverUrl = string(json, keys: ["customCoverUrl", "custom_cover_url"])
        book.localCoverPath = string(json, keys: ["localCoverPath", "local_cover_path"])
        book.intro = string(json, keys: ["intro", "description"])
        book.customIntro = string(json, keys: ["customIntro", "custom_intro"])
        book.type = BookType(rawValue: integer(json, keys: ["type"]) ?? 0) ?? .text
        book.group = integer64(json, keys: ["group"]) ?? 0
        book.latestChapterTitle = string(json, keys: ["latestChapterTitle", "latest_chapter_title"])
        book.latestChapterTime = integer64(json, keys: ["latestChapterTime", "latest_chapter_time"]) ?? book.latestChapterTime
        book.lastCheckTime = integer64(json, keys: ["lastCheckTime", "last_check_time"]) ?? book.lastCheckTime
        book.lastCheckCount = integer(json, keys: ["lastCheckCount", "last_check_count"]) ?? 0
        book.totalChapterNum = integer(json, keys: ["totalChapterNum", "total_chapter_num"]) ?? 0
        book.durChapterTitle = string(json, keys: ["durChapterTitle", "dur_chapter_title"])
        book.durChapterIndex = integer(json, keys: ["durChapterIndex", "dur_chapter_index"]) ?? 0
        book.durChapterPos = integer(json, keys: ["durChapterPos", "dur_chapter_pos"]) ?? 0
        book.durChapterTime = integer64(json, keys: ["durChapterTime", "dur_chapter_time"]) ?? book.durChapterTime
        book.wordCount = string(json, keys: ["wordCount", "word_count"])
        book.canUpdate = boolean(json, keys: ["canUpdate", "can_update"]) ?? true
        book.order = integer(json, keys: ["order"]) ?? 0
        book.originOrder = integer(json, keys: ["originOrder", "origin_order"]) ?? 0
        book.variable = string(json, keys: ["variable"])
        book.skipDetailPage = boolean(json, keys: ["skipDetailPage", "skip_detail_page"]) ?? false
        return book
    }

    private static func string(_ json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String { return value }
            if let value = json[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    private static func integer(_ json: [String: Any], keys: [String]) -> Int? {
        guard let value = integer64(json, keys: keys) else { return nil }
        return Int(value)
    }

    private static func integer64(_ json: [String: Any], keys: [String]) -> Int64? {
        for key in keys {
            if let value = json[key] as? NSNumber { return value.int64Value }
            if let value = json[key] as? String, let number = Int64(value) { return number }
        }
        return nil
    }

    private static func boolean(_ json: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = json[key] as? Bool { return value }
            if let value = json[key] as? NSNumber { return value.boolValue }
            if let value = json[key] as? String {
                if ["true", "1", "yes"].contains(value.lowercased()) { return true }
                if ["false", "0", "no"].contains(value.lowercased()) { return false }
            }
        }
        return nil
    }

    private static var error: NSError {
        NSError(domain: "BookImport", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "不是可识别的 Legado 书架 JSON"
        ])
    }
}
