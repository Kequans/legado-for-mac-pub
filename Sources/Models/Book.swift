import Foundation

/// 书籍模型
struct Book: Identifiable, Codable, Hashable {
    var id: String { bookUrl }
    
    // 基本信息
    var bookUrl: String                    // 详情页URL（本地书源存储完整文件路径）
    var tocUrl: String = ""                // 目录页URL
    var origin: String = "local"           // 书源URL
    var originName: String = ""            // 书源名称
    var name: String                       // 书籍名称
    var author: String                     // 作者名称
    var kind: String?                      // 分类信息（书源获取）
    var customTag: String?                 // 分类信息（用户修改）
    var coverUrl: String?                  // 封面URL
    var customCoverUrl: String?            // 自定义封面URL
    var localCoverPath: String?            // 本地封面缓存路径
    var intro: String?                     // 简介
    var customIntro: String?               // 自定义简介
    
    // 类型和分组
    var type: BookType = .text             // 书籍类型
    var group: Int64 = 0                   // 自定义分组
    
    // 章节信息
    var latestChapterTitle: String?        // 最新章节标题
    var latestChapterTime: Int64 = 0       // 最新章节时间
    var lastCheckTime: Int64 = 0           // 最后检查时间
    var lastCheckCount: Int = 0            // 最后检查新增章节数
    var totalChapterNum: Int = 0           // 章节总数
    
    // 阅读进度
    var durChapterTitle: String?           // 当前章节标题
    var durChapterIndex: Int = 0           // 当前章节索引
    var durChapterPos: Int = 0             // 当前阅读位置
    var durChapterTime: Int64 = 0          // 当前章节时间
    
    // 其他配置
    var wordCount: String?                 // 字数
    var canUpdate: Bool = true             // 是否可更新
    var order: Int = 0                     // 排序
    var originOrder: Int = 0               // 原始顺序
    var variable: String?                  // 自定义变量
    var skipDetailPage: Bool = false       // 是否跳过详情页（针对该书）
    
    // 辅助属性
    var isLocal: Bool {
        origin == "local" || origin.isEmpty
    }
    
    var displayCover: String {
        // 优先使用本地缓存路径
        if let localPath = localCoverPath, !localPath.isEmpty {
            return localPath
        }
        return customCoverUrl ?? coverUrl ?? ""
    }
    
    var displayIntro: String {
        customIntro ?? intro ?? "暂无简介"
    }
    
    // 初始化
    init(bookUrl: String, name: String, author: String) {
        self.bookUrl = bookUrl
        self.name = name
        self.author = author
        self.latestChapterTime = Int64(Date().timeIntervalSince1970)
        self.lastCheckTime = Int64(Date().timeIntervalSince1970)
        self.durChapterTime = Int64(Date().timeIntervalSince1970)
    }
}

/// 书籍类型
enum BookType: Int, Codable {
    case text = 0      // 文本
    case audio = 1     // 音频
    case image = 2     // 图片/漫画
    case file = 3      // 文件
    
    var description: String {
        switch self {
        case .text: return "文本"
        case .audio: return "音频"
        case .image: return "漫画"
        case .file: return "文件"
        }
    }
}

extension Book {
    // 示例数据
    static let example = Book(
        bookUrl: "example://book/1",
        name: "示例书籍",
        author: "示例作者"
    )
}
