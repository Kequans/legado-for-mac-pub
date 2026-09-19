import Foundation

/// 章节内容缓存模型
struct ChapterContent: Identifiable, Codable {
    var id: String { chapterUrl }
    
    var chapterUrl: String      // 章节URL
    var bookUrl: String         // 书籍URL
    var content: String         // 章节内容
    var cachedTime: Int64       // 缓存时间戳
    
    init(chapterUrl: String, bookUrl: String, content: String) {
        self.chapterUrl = chapterUrl
        self.bookUrl = bookUrl
        self.content = content
        self.cachedTime = Int64(Date().timeIntervalSince1970)
    }
}
