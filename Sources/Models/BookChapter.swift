import Foundation

/// 章节模型
struct BookChapter: Identifiable, Codable, Hashable {
    var id: String { url }
    
    var url: String                        // 章节URL
    var title: String                      // 章节标题
    var bookUrl: String                    // 书籍URL
    var index: Int                         // 章节序号
    
    var isVip: Bool = false                // 是否VIP
    var isPay: Bool = false                // 是否付费
    var resourceUrl: String?               // 音频/图片地址
    var tag: String?                       // 标签
    var start: Int64?                      // 章节起始位置（本地规范化源文件的 UTF-8 字节偏移）
    var end: Int64?                        // 章节结束位置（本地规范化源文件的 UTF-8 字节偏移）
    var variable: String?                  // 变量
    var startFragmentId: String?           // EPUB章节锚点
    var endFragmentId: String?             // EPUB章节锚点
    
    init(url: String, title: String, bookUrl: String, index: Int) {
        self.url = url
        self.title = title
        self.bookUrl = bookUrl
        self.index = index
    }
}

extension BookChapter {
    static let example = BookChapter(
        url: "chapter1",
        title: "第一章",
        bookUrl: "example://book/1",
        index: 0
    )
}
