import Foundation

/// 书签模型
struct Bookmark: Identifiable, Codable, Hashable {
    var id = UUID()
    
    var bookUrl: String                    // 书籍URL
    var bookName: String                   // 书籍名称
    var chapterIndex: Int                  // 章节索引
    var chapterPos: Int                    // 章节位置
    var chapterName: String                // 章节名称
    var bookText: String                   // 书签文本
    var content: String                    // 书签内容
    var time: Int64                        // 创建时间
    
    init(bookUrl: String, bookName: String, chapterIndex: Int, chapterPos: Int, chapterName: String, bookText: String, content: String) {
        self.bookUrl = bookUrl
        self.bookName = bookName
        self.chapterIndex = chapterIndex
        self.chapterPos = chapterPos
        self.chapterName = chapterName
        self.bookText = bookText
        self.content = content
        self.time = Int64(Date().timeIntervalSince1970)
    }
}

/// 阅读记录
struct ReadRecord: Identifiable, Codable, Hashable {
    var id: String { bookName + "_" + "\(time)" }
    
    var bookName: String                   // 书籍名称
    var readTime: Int64                    // 阅读时间（秒）
    var time: Int64                        // 记录时间
    
    init(bookName: String, readTime: Int64) {
        self.bookName = bookName
        self.readTime = readTime
        self.time = Int64(Date().timeIntervalSince1970)
    }
}

/// 替换规则
struct ReplaceRule: Identifiable, Codable, Hashable {
    var id = UUID()
    
    var name: String                       // 规则名称
    var group: String?                     // 分组
    var pattern: String                    // 替换规则
    var replacement: String                // 替换为
    var order: Int = 0                     // 顺序
    var enabled: Bool = true               // 是否启用
    var isRegex: Bool = true               // 是否正则
    var scope: String?                     // 作用域
    
    init(name: String, pattern: String, replacement: String) {
        self.name = name
        self.pattern = pattern
        self.replacement = replacement
    }
}
